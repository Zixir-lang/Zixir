"""
VectorDB Protocol Bridge for Zixir

Provides JSON-RPC style interface for Elixir integration.
Allows Elixir to call Python vector database operations.
"""

import json
import sys
from typing import Any, Dict, List, Optional
from vector_db_bridge import VectorDBBridge, SearchResult

# Protocol version
PROTOCOL_VERSION = "1.0"

def bridge_init(backend: str, config: Dict) -> Dict:
    """Initialize a vector database backend."""
    try:
        backend_map = {
            "memory": "memory",
            "chroma": "chroma",
            "pinecone": "pinecone",
            "weaviate": "weaviate",
            "qdrant": "qdrant",
            "milvus": "milvus"
        }

        normalized_backend = backend_map.get(backend.lower(), "memory")

        kwargs = {
            "backend": normalized_backend,
            "collection": config.get("collection", config.get("class_name", "default")),
            "host": config.get("host"),
            "api_key": config.get("api_key"),
            "dimensions": config.get("dimensions", 384),
            "metric": config.get("metric", "cosine")
        }

        # Filter out None values
        kwargs = {k: v for k, v in kwargs.items() if v is not None}

        bridge = VectorDBBridge(**kwargs)

        return {
            "status": "ok",
            "state": {
                "backend": normalized_backend,
                "collection": kwargs.get("collection", "default"),
                "initialized": True
            }
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_add(state: Dict, doc_id: str, embedding: List[float], metadata: Dict) -> Dict:
    """Add a document to the database."""
    try:
        # Re-create bridge from state (in production, we'd serialize properly)
        bridge = _restore_bridge(state)
        bridge.add(doc_id, embedding, metadata or {})

        return {
            "status": "ok",
            "state": state
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_add_batch(state: Dict, documents: List[Dict]) -> Dict:
    """Add multiple documents."""
    try:
        bridge = _restore_bridge(state)
        count = bridge.add_batch(documents)

        return {
            "status": "ok",
            "state": state,
            "count": count
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_search(state: Dict, query: List[float], top_k: int, filter: Optional[Dict], include_embeddings: bool) -> Dict:
    """Search for similar documents."""
    try:
        bridge = _restore_bridge(state)
        results = bridge.search(
            query_embedding=query,
            top_k=top_k,
            filter=filter,
            include_embeddings=include_embeddings
        )

        parsed_results = [
            {
                "id": r.id,
                "score": r.score,
                "embedding": r.embedding,
                "metadata": r.metadata
            }
            for r in results
        ]

        return {
            "status": "ok",
            "results": parsed_results
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_get(state: Dict, doc_id: str) -> Dict:
    """Get a document by ID."""
    try:
        bridge = _restore_bridge(state)
        result = bridge.get(doc_id)

        if result:
            return {
                "status": "ok",
                "document": {
                    "id": result.get("id", doc_id),
                    "embedding": result.get("embedding"),
                    "metadata": result.get("metadata", {})
                }
            }
        else:
            return {
                "status": "error",
                "message": "Document not found"
            }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_delete(state: Dict, doc_id: str) -> Dict:
    """Delete a document."""
    try:
        bridge = _restore_bridge(state)
        bridge.delete(doc_id)

        return {
            "status": "ok",
            "state": state
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_update_metadata(state: Dict, doc_id: str, metadata: Dict) -> Dict:
    """Update document metadata."""
    try:
        bridge = _restore_bridge(state)
        bridge.update_metadata(doc_id, metadata)

        return {
            "status": "ok"
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_count(state: Dict) -> Dict:
    """Get document count."""
    try:
        bridge = _restore_bridge(state)
        n = bridge.count()

        return {
            "status": "ok",
            "count": n
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_stats(state: Dict) -> Dict:
    """Get database statistics."""
    try:
        bridge = _restore_bridge(state)
        stats = bridge.stats()

        return {
            "status": "ok",
            "stats": stats
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_close(state: Dict) -> Dict:
    """Close database connection."""
    try:
        bridge = _restore_bridge(state)
        bridge.close()

        return {
            "status": "ok"
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def bridge_available_backends() -> Dict:
    """Check which backends are available."""
    return {
        "status": "ok",
        "backends": VectorDBBridge.available_backends()
    }

def _restore_bridge(state: Dict) -> VectorDBBridge:
    """Restore a VectorDBBridge from state."""
    # In production, we'd properly serialize/deserialize
    # For now, reinitialize with stored config
    return VectorDBBridge(
        backend=state.get("backend", "memory"),
        collection=state.get("collection", "default"),
        dimensions=state.get("dimensions", 384)
    )

# JSON-RPC style dispatcher
def handle_request(request: Dict) -> Dict:
    """Handle a JSON-RPC style request."""
    method = request.get("method")
    params = request.get("params", {})

    handlers = {
        "init": lambda: bridge_init(params.get("backend"), params.get("config", {})),
        "add": lambda: bridge_add(
            params.get("state", {}),
            params.get("id"),
            params.get("embedding", []),
            params.get("metadata", {})
        ),
        "add_batch": lambda: bridge_add_batch(
            params.get("state", {}),
            params.get("documents", [])
        ),
        "search": lambda: bridge_search(
            params.get("state", {}),
            params.get("query", []),
            params.get("top_k", 10),
            params.get("filter"),
            params.get("include_embeddings", False)
        ),
        "get": lambda: bridge_get(params.get("state", {}), params.get("id")),
        "delete": lambda: bridge_delete(params.get("state", {}), params.get("id")),
        "update_metadata": lambda: bridge_update_metadata(
            params.get("state", {}),
            params.get("id"),
            params.get("metadata", {})
        ),
        "count": lambda: bridge_count(params.get("state", {})),
        "stats": lambda: bridge_stats(params.get("state", {})),
        "close": lambda: bridge_close(params.get("state", {})),
        "available_backends": lambda: bridge_available_backends()
    }

    handler = handlers.get(method)
    if handler:
        return handler()
    else:
        return {
            "status": "error",
            "message": f"Unknown method: {method}"
        }

# Main entry point for stdin/stdout communication
if __name__ == "__main__":
    """Read JSON requests from stdin, write responses to stdout."""
    import sys

    for line in sys.stdin:
        try:
            request = json.loads(line.strip())
            response = handle_request(request)
            print(json.dumps(response), flush=True)
        except json.JSONDecodeError as e:
            print(json.dumps({
                "status": "error",
                "message": f"Invalid JSON: {str(e)}"
            }), flush=True)
        except Exception as e:
            print(json.dumps({
                "status": "error",
                "message": str(e)
            }), flush=True)
