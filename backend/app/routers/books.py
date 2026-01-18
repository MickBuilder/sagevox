"""Books API router for listing and retrieving audiobook metadata."""

import logging

from fastapi import APIRouter, HTTPException, Request

from ..services.library import (
    get_books_dir,
    load_book_metadata,
    get_book_with_chapters,
)
from ..models.book import Book, BookSummary

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/books", tags=["books"])

# Log when this module is imported (helps debug Railway deployment)
_books_dir = get_books_dir()
logger.info(f"Books router loaded. Books directory: {_books_dir}, exists: {_books_dir.exists()}")


@router.get("/debug")
async def debug_books() -> dict:
    """Debug endpoint to check books directory status."""
    books_dir = get_books_dir()
    contents = []
    if books_dir.exists():
        try:
            contents = [str(p.name) for p in books_dir.iterdir()]
        except Exception as e:
            contents = [f"Error listing: {e}"]
    return {
        "books_dir": str(books_dir),
        "exists": books_dir.exists(),
        "is_dir": books_dir.is_dir() if books_dir.exists() else False,
        "contents": contents,
    }


@router.get("", response_model=list[BookSummary])
async def list_books(request: Request) -> list[BookSummary]:
    """List all available books in the library."""
    books_dir = get_books_dir()
    logger.info(f"list_books called. books_dir={books_dir}, exists={books_dir.exists()}")

    if not books_dir.exists():
        logger.warning(f"Books directory not found: {books_dir}")
        return []
    
    books: list[BookSummary] = []
    
    # Scan for book directories
    for item in books_dir.iterdir():
        if not item.is_dir():
            continue
        
        metadata = load_book_metadata(item)
        if metadata is None:
            continue
        
        # Construct cover URL if cover exists
        cover_url = None
        if metadata.cover_image:
            # Build absolute URL for cover image
            cover_url = str(request.url_for("books_static", path=f"{metadata.id}/{metadata.cover_image}"))
        
        books.append(BookSummary(
            id=metadata.id,
            title=metadata.title,
            author=metadata.author,
            description=metadata.description,
            cover_url=cover_url,
            total_chapters=metadata.total_chapters,
            total_duration_seconds=metadata.total_duration_seconds,
        ))
    
    # Sort by title
    books.sort(key=lambda b: b.title)
    
    logger.info(f"Found {len(books)} books")
    return books


@router.get("/{book_id}", response_model=Book)
async def get_book(book_id: str) -> Book:
    """Get full book metadata with chapters and embedded transcripts."""
    book = get_book_with_chapters(book_id)
    
    if book is None:
        raise HTTPException(status_code=404, detail=f"Book not found: {book_id}")
    
    return book
