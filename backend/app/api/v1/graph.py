"""API endpoint for serving the Graphify knowledge graph HTML.

GET /api/v1/graph — returns the interactive graph HTML page
"""
from __future__ import annotations

import os

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(prefix="/graph", tags=["graph"])

# Path to graphify output (project root)
_PROJECT_ROOT = os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
))
_GRAPH_HTML_PATH = os.path.join(_PROJECT_ROOT, "graphify-out", "graph.html")


@router.get("", response_class=HTMLResponse)
async def get_graph() -> HTMLResponse:
    """Return the interactive graph HTML page."""
    if not os.path.exists(_GRAPH_HTML_PATH):
        return HTMLResponse(
            content="<html><body><h1>Граф ещё не построен</h1>"
            "<p>Запусти <code>graphify .</code> в корне проекта.</p></body></html>",
            status_code=200,
        )
    with open(_GRAPH_HTML_PATH, encoding="utf-8") as f:
        content = f.read()
    return HTMLResponse(content=content)
