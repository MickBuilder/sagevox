"""Command-line interface for SageVox Converter."""

import sys
from pathlib import Path
from typing import Optional

import click
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn
from rich.table import Table
from rich.prompt import Prompt
from dotenv import load_dotenv

from .models import BookMetadata
from .epub_parser import parse_epub, parse_epub_sections, sections_to_chapters, create_book_metadata
from .tts_service import GeminiTTSService


load_dotenv()
console = Console()


def slugify(text: str) -> str:
    import re
    text = text.lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_-]+", "-", text)
    return text.strip("-")


def parse_section_selection(selection: str, max_index: int) -> list[int]:
    indices = []
    for part in selection.replace(" ", "").split(","):
        if "-" in part:
            try:
                start, end = part.split("-", 1)
                indices.extend(range(int(start), int(end) + 1))
            except ValueError:
                continue
        else:
            try:
                indices.append(int(part))
            except ValueError:
                continue
    return sorted(set(i for i in indices if 1 <= i <= max_index))


@click.group()
@click.version_option(version="0.1.0")
def main():
    """SageVox Converter - Transform ePub books into interactive audiobooks."""
    pass


@main.command()
@click.argument("epub_path", type=click.Path(exists=True, path_type=Path))
def sections(epub_path: Path):
    """List all sections in an ePub file."""
    console.print(f"\n[bold blue]SageVox - Section Viewer[/bold blue]")
    console.print(f"File: [cyan]{epub_path}[/cyan]\n")
    
    with console.status("[bold green]Parsing ePub..."):
        try:
            parsed = parse_epub_sections(epub_path)
        except Exception as e:
            console.print(f"[red]Error:[/red] {e}")
            sys.exit(1)
    
    console.print(f"[green]Title:[/green] {parsed.title}")
    console.print(f"[green]Author:[/green] {parsed.author}")
    console.print(f"[green]Sections:[/green] {len(parsed.sections)}\n")
    
    table = Table(title="All Sections")
    table.add_column("#", style="cyan", width=4)
    table.add_column("Title", style="white", width=50)
    table.add_column("Words", style="green", width=8, justify="right")
    
    for s in parsed.sections:
        table.add_row(str(s.index), s.title[:49] + "…" if len(s.title) > 50 else s.title, str(s.word_count))
    
    console.print(table)
    console.print(f"\n[dim]Usage: sagevox-convert convert {epub_path} --sections 3-15,17[/dim]")


@main.command()
@click.argument("epub_path", type=click.Path(exists=True, path_type=Path))
@click.option("-o", "--output", type=click.Path(path_type=Path), help="Output directory")
@click.option("-v", "--voice", default="Kore", type=click.Choice(GeminiTTSService.AVAILABLE_VOICES, case_sensitive=False))
@click.option("-l", "--language", default="en-US", help="Language code")
@click.option("--narrator-style", type=click.Choice(["classic", "dramatic", "calm", "energetic"], case_sensitive=False), default="classic", help="Narrator style preset")
@click.option("--style", default=None, help="Custom style prompt (overrides --narrator-style)")
@click.option("--sections", "section_selection", type=str, help="Sections to convert (e.g., '3-15,17')")
@click.option("-i", "--interactive", is_flag=True, help="Interactively select sections")
@click.option("--start-chapter", type=int, default=1)
@click.option("--end-chapter", type=int, default=None)
@click.option("--dry-run", is_flag=True, help="Parse only, don't generate")
@click.option("--skip-existing/--no-skip-existing", default=True)
@click.option("--force", is_flag=True, help="Overwrite existing")
@click.option("--include-headings", is_flag=True, help="Include H1-H6 in audio")
def convert(
    epub_path: Path,
    output: Optional[Path],
    voice: str,
    language: str,
    narrator_style: str,
    style: Optional[str],
    section_selection: Optional[str],
    interactive: bool,
    start_chapter: int,
    end_chapter: Optional[int],
    dry_run: bool,
    skip_existing: bool,
    force: bool,
    include_headings: bool,
):
    """Convert an ePub file to a SageVox audiobook."""
    console.print(f"\n[bold blue]SageVox Converter[/bold blue]")
    console.print(f"Converting: [cyan]{epub_path}[/cyan]\n")
    
    with console.status("[bold green]Parsing ePub..."):
        try:
            parsed = parse_epub_sections(epub_path)
        except Exception as e:
            console.print(f"[red]Error:[/red] {e}")
            sys.exit(1)
    
    console.print(f"[green]Title:[/green] {parsed.title}")
    console.print(f"[green]Author:[/green] {parsed.author}")
    
    
    # 1. Generate the Canonical Chapter List (All valid content)
    # This prevents renumbering relative to selection. Chapter 1 is always Chapter 1.
    
    # Use auto-detection for the base list references if no explicit all-sections logic
    # But we want to respect the user's view of "sections" if possible.
    # The safest way: Use parse_epub logic to define "What is a chapter" by default.
    # If the user supplied specific sections, we assume those ARE the chapters they care about?
    # No, usually they select specific chapters to process from the whole.
    
    all_content_indices = []
    
    # Logic from parse_epub default filtering
    front_matter_patterns = [
        r"table\s*of\s*contents", r"^contents$", r"^toc$", r"copyright",
        r"dedication", r"acknowledgments?", r"title\s*page",
        r"about\s*the\s*author", r"also\s*by", r"^cover$",
    ]
    import re
    
    for section in parsed.sections:
        # Default criteria
        if section.word_count < 100: continue
        is_front = False
        for p in front_matter_patterns:
            if re.search(p, section.title.lower(), re.IGNORECASE):
                is_front = True; break
        if not is_front:
            all_content_indices.append(section.index)

    # If user selected specific sections, we treat those as the target for processing,
    # BUT we still define the book structure based on ALL content (unless we want to redefine the book).
    # Assuming user wants to build the "Whole Book" piece by piece.
    
    parsed.chapters = sections_to_chapters(parsed.sections, all_content_indices, not include_headings)
    
    # 2. Identify Metadata & Output
    book_id = slugify(parsed.title)
    if output is None:
        output = Path("./output") / book_id
    output.mkdir(parents=True, exist_ok=True)
    
    # 3. Load Existing Metadata for Merge
    metadata_path = output / "metadata.json"
    existing_metadata = None
    if metadata_path.exists():
        try:
            existing_metadata = BookMetadata.load(metadata_path)
            console.print(f"[dim]Loaded existing metadata with {existing_metadata.total_chapters} chapters[/dim]")
        except Exception as e:
            console.print(f"[yellow]Could not load existing metadata: {e}[/yellow]")

    # Create new base metadata (with full structure)
    metadata = create_book_metadata(parsed, book_id, voice, language)
    
    # Merge existing audio/transcript data into the new structure
    if existing_metadata:
        # Map by Chapter Number
        existing_map = {ch.number: ch for ch in existing_metadata.chapters}
        for new_ch in metadata.chapters:
            if new_ch.number in existing_map:
                old_ch = existing_map[new_ch.number]
                # Preserve existing file refs if they exist
                if old_ch.audio_file:
                    new_ch.audio_file = old_ch.audio_file
                    new_ch.duration_seconds = old_ch.duration_seconds
                if old_ch.transcript_file:
                    new_ch.transcript_file = old_ch.transcript_file

    # 4. Determine Chapters to Process in this run
    chapters_to_process = []
    
    # Parse section selection if provided
    selected_indices = None
    if section_selection:
        selected_indices = parse_section_selection(section_selection, len(parsed.sections))
        if not selected_indices:
            console.print(f"[yellow]Warning: No valid sections in '{section_selection}'[/yellow]")
    elif interactive:
        # Show sections and prompt for selection
        table = Table(title="Available Sections")
        table.add_column("#", style="cyan", width=4)
        table.add_column("Title", style="white", width=50)
        table.add_column("Words", style="green", width=8, justify="right")
        
        for s in parsed.sections:
            if s.index in all_content_indices:
                table.add_row(str(s.index), s.title[:49] + "…" if len(s.title) > 50 else s.title, str(s.word_count))
        
        console.print(table)
        selection = Prompt.ask("\nEnter sections to convert (e.g., '1-5,7,10-12')", default="all")
        if selection.lower() != "all":
            selected_indices = parse_section_selection(selection, len(parsed.sections))
    
    if selected_indices:
        # We need to map Chapter -> Section Index. 
        # Since sections_to_chapters lost that info, we reconstruct the map roughly:
        # parsed.chapters corresponds 1:1 to all_content_indices.
        if len(parsed.chapters) == len(all_content_indices):
            for i, ch in enumerate(parsed.chapters):
                section_idx = all_content_indices[i]
                if section_idx in selected_indices:
                    chapters_to_process.append(ch)
        else:
            console.print("[red]Warning: Chapter/Section mapping mismatch. Converting based on selection impossible (fallback to all).[/red]")
            chapters_to_process = parsed.chapters
    else:
        # Convert range (start/end chapter) or all
        chapters_to_process = [
            ch for ch in metadata.chapters
            if ch.number >= start_chapter and (end_chapter is None or ch.number <= end_chapter)
        ]

    console.print(f"[green]Total Book Chapters:[/green] {len(metadata.chapters)}")
    console.print(f"[green]Chapters to Process:[/green] {len(chapters_to_process)}")
    
    if not chapters_to_process:
        console.print("[yellow]No chapters selected for conversion[/yellow]")
        return
        
    if dry_run:
        for ch in chapters_to_process:
            console.print(f"  {ch.number}. {ch.title}")
        console.print("\n[yellow]Dry run - no audio generated[/yellow]")
        return

    console.print(f"[green]Output:[/green] {output}")
    console.print(f"[green]Voice:[/green] {voice}")
    console.print(f"[green]Narrator Style:[/green] {narrator_style}" + (" (custom)" if style else "") + "\n")
    
    if parsed.cover_data:
        cover_path = output / f"cover.{parsed.cover_extension}"
        with open(cover_path, "wb") as f:
            f.write(parsed.cover_data)
        metadata.cover_image = cover_path.name
    
    tts = GeminiTTSService(voice=voice, language_code=language)
    
    skip_existing_chapters = skip_existing and not force
    
    # Calculate total duration from metadata (including existing) + updates
    # We will update individual chapters and assume the sum is correct at end.
    
    skipped = 0
    generated_count = 0
    
    with Progress(
        SpinnerColumn(), TextColumn("[progress.description]{task.description}"),
        BarColumn(), TaskProgressColumn(), console=console,
    ) as progress:
        task = progress.add_task("Converting...", total=len(chapters_to_process))
        
        for chapter in chapters_to_process:
            progress.update(task, description=f"Chapter {chapter.number}: {chapter.title[:25]}...")
            
            mp3_path = output / f"chapter-{chapter.number:02d}.mp3"
            wav_path = output / f"chapter-{chapter.number:02d}.wav"
            transcript_path = output / f"chapter-{chapter.number:02d}-transcript.json"
            
            # Skip existing
            if skip_existing_chapters and (mp3_path.exists() or wav_path.exists()):
                # Update metadata if needed
                existing = mp3_path if mp3_path.exists() else wav_path
                try:
                    import wave
                    if existing.suffix == '.wav':
                        with wave.open(str(existing), 'rb') as wf:
                            duration = wf.getnframes() / float(wf.getframerate())
                    else:
                        duration = existing.stat().st_size / 24000 # Rough approx if MP3
                        # Ideally load metadata duration
                    
                    chapter.audio_file = existing.name
                    if chapter.duration_seconds == 0: chapter.duration_seconds = duration
                    if transcript_path.exists():
                        chapter.transcript_file = transcript_path.name
                    
                    skipped += 1
                    progress.advance(task)
                    continue
                except Exception:
                    pass
            
            try:
                # Generate audio + transcript
                audio_file, duration, transcript = tts.synthesize_chapter(
                    chapter, 
                    output, 
                    style_prompt=style,
                    narrator_style=narrator_style
                )
                
                chapter.audio_file = audio_file
                chapter.duration_seconds = duration
                
                # Save transcript
                transcript_file = f"chapter-{chapter.number:02d}-transcript.json"
                transcript.save(output / transcript_file)
                chapter.transcript_file = transcript_file
                
                generated_count += 1
                
            except Exception as e:
                console.print(f"\n[red]Error on chapter {chapter.number}:[/red] {e}")
                continue
            
            progress.advance(task)
    
    if skipped > 0:
        console.print(f"[yellow]Skipped {skipped} existing[/yellow]")
    
    # Recalculate total duration
    total_duration = sum(ch.duration_seconds for ch in metadata.chapters)
    metadata.total_duration_seconds = total_duration
    metadata.save(output)
    
    hours = int(total_duration // 3600)
    minutes = int((total_duration % 3600) // 60)
    console.print(f"\n[bold green]Done![/bold green] {hours}h {minutes}m")
    console.print(f"Output: {output}")


@main.command()
def voices():
    """List available narrator voices."""
    table = Table(title="Available Voices")
    table.add_column("Voice", style="cyan")
    table.add_column("Style")
    
    voices = {
        "Kore": "Firm", "Charon": "Informative", "Puck": "Upbeat",
        "Fenrir": "Excitable", "Aoede": "Breezy", "Leda": "Youthful",
        "Zephyr": "Bright", "Orus": "Firm", "Autonoe": "Bright",
        "Enceladus": "Breathy", "Iapetus": "Clear", "Umbriel": "Easy-going",
        "Algieba": "Smooth", "Despina": "Smooth", "Erinome": "Clear",
        "Algenib": "Gravelly", "Rasalgethi": "Informative",
        "Laomedeia": "Upbeat", "Achernar": "Soft", "Alnilam": "Firm",
        "Schedar": "Even", "Gacrux": "Mature", "Pulcherrima": "Forward",
        "Achird": "Friendly", "Zubenelgenubi": "Casual",
        "Vindemiatrix": "Gentle", "Sadachbia": "Lively",
        "Sadaltager": "Knowledgeable", "Sulafat": "Warm",
    }
    for v, s in voices.items():
        table.add_row(v, s)
    console.print(table)


@main.command()
@click.argument("metadata_path", type=click.Path(exists=True, path_type=Path))
def info(metadata_path: Path):
    """Show audiobook info."""
    m = BookMetadata.load(metadata_path)
    console.print(f"\n[bold blue]{m.title}[/bold blue] by {m.author}")
    console.print(f"Voice: {m.narrator_voice} | Chapters: {m.total_chapters}")
    h, mins = int(m.total_duration_seconds // 3600), int((m.total_duration_seconds % 3600) // 60)
    console.print(f"Duration: {h}h {mins}m")


if __name__ == "__main__":
    main()
