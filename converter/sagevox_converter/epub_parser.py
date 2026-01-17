"""ePub parsing and chapter extraction with ToC-based section detection."""

import re
from pathlib import Path
from typing import Optional
from dataclasses import dataclass, field
from urllib.parse import unquote

import ebooklib
from ebooklib import epub
from bs4 import BeautifulSoup, NavigableString

from .models import Chapter, BookMetadata


@dataclass
class Section:
    """Represents a section/document in the ePub."""
    index: int
    name: str  # Original file name in ePub
    title: str  # Extracted title
    word_count: int
    text_content: str
    raw_html: str
    

@dataclass
class ParsedEpub:
    """Result of parsing an ePub file."""
    title: str
    author: str
    description: str
    sections: list[Section] = field(default_factory=list)
    chapters: list[Chapter] = field(default_factory=list)
    cover_data: Optional[bytes] = None
    cover_extension: str = "jpg"


# Patterns for front/back matter to skip
SKIP_PATTERNS = [
    r"table\s*of\s*contents",
    r"^contents$",
    r"^toc$",
    r"copyright",
    r"^cover$",
    r"full\s*project\s*gutenberg\s*license",
    r"^wrap\d+$",
    r"transcriber'?s?\s*note",
]


def _should_skip_toc_entry(title: str) -> bool:
    """Check if a ToC entry should be skipped (front/back matter)."""
    title_lower = title.lower().strip()
    for pattern in SKIP_PATTERNS:
        if re.search(pattern, title_lower, re.IGNORECASE):
            return True
    return False


def _flatten_toc(toc: list) -> list[tuple[str, str]]:
    """Flatten nested ToC structure into list of (title, href) tuples."""
    result = []
    
    for item in toc:
        if isinstance(item, tuple):
            # Nested section: (Link, [children])
            section, children = item
            if hasattr(section, 'title') and hasattr(section, 'href'):
                result.append((section.title, section.href))
            # Recursively process children
            if isinstance(children, list):
                result.extend(_flatten_toc(children))
        elif hasattr(item, 'title') and hasattr(item, 'href'):
            # Simple Link object
            result.append((item.title, item.href))
    
    return result


def _extract_content_from_anchor(soup: BeautifulSoup, anchor_id: str, next_anchor_id: Optional[str] = None) -> str:
    """Extract text content starting from anchor_id until next_anchor_id (or end).
    
    Args:
        soup: Parsed HTML document
        anchor_id: Starting anchor ID (without #)
        next_anchor_id: Ending anchor ID (without #), or None for end of document
        
    Returns:
        Extracted text content
    """
    start_elem = soup.find(id=anchor_id)
    if not start_elem:
        return ""
    
    # Collect text from start element until we hit the next anchor
    texts = []
    
    # Include the start element's text
    texts.append(start_elem.get_text(separator=" "))
    
    # Walk through siblings after the start element
    for sibling in start_elem.find_next_siblings():
        # Stop if we hit the next chapter anchor
        if next_anchor_id and sibling.get('id') == next_anchor_id:
            break
        # Also check if next anchor is inside this sibling
        if next_anchor_id:
            nested = sibling.find(id=next_anchor_id)
            if nested:
                # Get text before the nested anchor
                break
        texts.append(sibling.get_text(separator=" "))
    
    text = " ".join(texts)
    # Clean up whitespace
    text = re.sub(r"\s+", " ", text).strip()
    return text


def clean_text(html_content: str, exclude_headings: bool = False) -> str:
    """Extract and clean text from HTML content.
    
    Args:
        html_content: Raw HTML content
        exclude_headings: If True, remove H1-H6 headings from output
        
    Returns:
        Cleaned text content
    """
    soup = BeautifulSoup(html_content, "html.parser")
    
    # Remove script and style elements
    for element in soup(["script", "style", "nav", "header", "footer"]):
        element.decompose()
    
    # Remove headings if requested (for audio - we don't want to read "Chapter 1" etc)
    if exclude_headings:
        for element in soup(["h1", "h2", "h3", "h4", "h5", "h6"]):
            element.decompose()
    
    # Get text and clean it up
    text = soup.get_text(separator=" ")
    
    # Clean up whitespace
    text = re.sub(r"\s+", " ", text)
    text = text.strip()
    
    # Clean up common issues
    text = re.sub(r"\s+([.,!?;:])", r"\1", text)  # Remove space before punctuation
    text = re.sub(r"([.!?])\s*([A-Z])", r"\1 \2", text)  # Ensure space after sentence
    
    return text


def extract_section_title(content: str, fallback_name: str) -> str:
    """Extract section title from content."""
    soup = BeautifulSoup(content, "html.parser")
    
    # Try to find a heading
    for tag in ["h1", "h2", "h3", "title"]:
        heading = soup.find(tag)
        if heading:
            title = heading.get_text().strip()
            if title and len(title) < 150:
                return title
    
    # Use filename without extension as fallback
    return fallback_name.replace(".xhtml", "").replace(".html", "").replace("_", " ").title()


def parse_epub_sections(epub_path: Path) -> ParsedEpub:
    """Parse an ePub file using ToC for proper chapter detection.
    
    Uses the Table of Contents to detect chapters, even when multiple
    chapters exist within a single HTML file (common in Project Gutenberg).
    
    Args:
        epub_path: Path to the ePub file
        
    Returns:
        ParsedEpub with all sections listed
    """
    book = epub.read_epub(str(epub_path))
    
    # Extract metadata
    title = book.get_metadata("DC", "title")
    title = title[0][0] if title else epub_path.stem
    
    author = book.get_metadata("DC", "creator")
    author = author[0][0] if author else "Unknown Author"
    
    description = book.get_metadata("DC", "description")
    description = description[0][0] if description else ""
    
    # Try to extract cover image
    cover_data = None
    cover_extension = "jpg"
    for item in book.get_items():
        if item.get_type() == ebooklib.ITEM_COVER:
            cover_data = item.get_content()
            name = item.get_name().lower()
            if ".png" in name:
                cover_extension = "png"
            break
    
    # If no cover item, look for cover image
    if not cover_data:
        for item in book.get_items_of_type(ebooklib.ITEM_IMAGE):
            name = item.get_name().lower()
            if "cover" in name:
                cover_data = item.get_content()
                if ".png" in name:
                    cover_extension = "png"
                break
    
    # Build a cache of documents by name
    documents: dict[str, tuple[str, BeautifulSoup]] = {}
    for item in book.get_items_of_type(ebooklib.ITEM_DOCUMENT):
        item_name = item.get_name()
        content = item.get_content().decode("utf-8", errors="ignore")
        soup = BeautifulSoup(content, "html.parser")
        documents[item_name] = (content, soup)
    
    # Try ToC-based parsing first
    sections: list[Section] = []
    toc_entries = _flatten_toc(book.toc)
    
    if toc_entries:
        # Group ToC entries by file
        entries_by_file: dict[str, list[tuple[int, str, str]]] = {}
        for idx, (entry_title, href) in enumerate(toc_entries):
            # Parse href: "file.xhtml#anchor" or just "file.xhtml"
            if "#" in href:
                file_path, anchor = href.split("#", 1)
            else:
                file_path, anchor = href, ""
            
            # URL decode the file path
            file_path = unquote(file_path)
            
            if file_path not in entries_by_file:
                entries_by_file[file_path] = []
            entries_by_file[file_path].append((idx, entry_title, anchor))
        
        # Process each ToC entry
        section_idx = 0
        for toc_idx, (entry_title, href) in enumerate(toc_entries):
            # Skip front/back matter
            if _should_skip_toc_entry(entry_title):
                continue
            
            # Parse href
            if "#" in href:
                file_path, anchor = href.split("#", 1)
            else:
                file_path, anchor = href, ""
            
            file_path = unquote(file_path)
            
            # Find the document
            doc_item = None
            raw_content = ""
            soup = None
            
            for doc_name, (content, doc_soup) in documents.items():
                # Match by exact name or by basename
                if doc_name == file_path or doc_name.endswith(file_path) or file_path.endswith(doc_name.split("/")[-1]):
                    raw_content = content
                    soup = doc_soup
                    break
            
            if not soup:
                continue
            
            # Find the next anchor in the same file (to know where this section ends)
            next_anchor = None
            file_entries = entries_by_file.get(file_path, [])
            for i, (idx, _, anc) in enumerate(file_entries):
                if idx == toc_idx and i + 1 < len(file_entries):
                    next_anchor = file_entries[i + 1][2]
                    break
            
            # Extract content
            if anchor:
                text_content = _extract_content_from_anchor(soup, anchor, next_anchor)
            else:
                # No anchor - get full document text
                text_content = clean_text(raw_content, exclude_headings=False)
            
            word_count = len(text_content.split()) if text_content else 0
            
            # Skip empty sections
            if word_count < 10:
                continue
            
            section_idx += 1
            section = Section(
                index=section_idx,
                name=file_path.split("/")[-1] if "/" in file_path else file_path,
                title=entry_title,
                word_count=word_count,
                text_content=text_content,
                raw_html=raw_content,
            )
            sections.append(section)
    
    # Fallback to file-based parsing if ToC didn't produce sections
    if not sections:
        for idx, item in enumerate(book.get_items_of_type(ebooklib.ITEM_DOCUMENT), start=1):
            content = item.get_content().decode("utf-8", errors="ignore")
            text_content = clean_text(content, exclude_headings=False)
            
            # Get the file name
            name = item.get_name()
            if "/" in name:
                name = name.split("/")[-1]
            
            # Extract title
            section_title = extract_section_title(content, name)
            
            word_count = len(text_content.split()) if text_content else 0
            
            section = Section(
                index=idx,
                name=name,
                title=section_title,
                word_count=word_count,
                text_content=text_content,
                raw_html=content,
            )
            sections.append(section)
    
    return ParsedEpub(
        title=title,
        author=author,
        description=description,
        sections=sections,
        cover_data=cover_data,
        cover_extension=cover_extension,
    )


def sections_to_chapters(
    sections: list[Section],
    selected_indices: list[int],
    exclude_headings: bool = True,
) -> list[Chapter]:
    """Convert selected sections to chapters for conversion.
    
    Args:
        sections: All sections from the ePub
        selected_indices: List of section indices to include (1-based)
        exclude_headings: If True, remove H1-H6 from audio text
        
    Returns:
        List of Chapter objects ready for TTS
    """
    chapters: list[Chapter] = []
    chapter_num = 0
    
    for section in sections:
        if section.index in selected_indices:
            chapter_num += 1
            
            # Re-extract text without headings for audio
            if exclude_headings:
                text_content = clean_text(section.raw_html, exclude_headings=True)
            else:
                text_content = section.text_content
            
            # Skip if no content after removing headings
            if not text_content or len(text_content.strip()) < 50:
                continue
            
            chapter = Chapter(
                number=chapter_num,
                title=section.title,
                text_content=text_content,
            )
            chapters.append(chapter)
    
    return chapters


# Keep the old function for backward compatibility
def parse_epub(epub_path: Path) -> ParsedEpub:
    """Parse an ePub file (backward compatible - auto-filters sections).
    
    For more control, use parse_epub_sections() instead.
    """
    parsed = parse_epub_sections(epub_path)
    
    # Auto-select sections that look like content (not front/back matter)
    front_matter_patterns = [
        r"table\s*of\s*contents",
        r"^contents$",
        r"copyright",
        r"dedication",
        r"acknowledgments?",
        r"title\s*page",
        r"about\s*the\s*author",
        r"also\s*by",
        r"^cover$",
    ]
    
    selected = []
    for section in parsed.sections:
        title_lower = section.title.lower()
        
        # Skip very short sections
        if section.word_count < 100:
            continue
        
        # Skip front matter
        is_front_matter = False
        for pattern in front_matter_patterns:
            if re.search(pattern, title_lower, re.IGNORECASE):
                is_front_matter = True
                break
        
        if not is_front_matter:
            selected.append(section.index)
    
    parsed.chapters = sections_to_chapters(parsed.sections, selected, exclude_headings=True)
    return parsed


def create_book_metadata(
    parsed: ParsedEpub,
    book_id: str,
    voice: str = "Kore",
    language: str = "en-US",
) -> BookMetadata:
    """Create BookMetadata from parsed ePub.
    
    Args:
        parsed: ParsedEpub result
        book_id: Unique identifier for the book
        voice: Gemini-TTS voice name
        language: Language code
        
    Returns:
        BookMetadata ready for conversion
    """
    return BookMetadata(
        id=book_id,
        title=parsed.title,
        author=parsed.author,
        description=parsed.description,
        narrator_voice=voice,
        language_code=language,
        total_chapters=len(parsed.chapters),
        chapters=parsed.chapters,
    )
