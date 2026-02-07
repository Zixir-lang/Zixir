"""
Unified Vector Database Bridge for Zixir

Provides a single interface to multiple vector databases via their Python clients.
Supports: Chroma, Pinecone, Weaviate, Qdrant, Milvus, and in-memory fallback.

Usage:
    from vector_db_bridge import VectorDBBridge

    bridge = VectorDBBridge(backend="chroma", collection="my_docs", host="localhost:8000")
    bridge.add(doc_id, embedding, metadata)
    results = bridge.search(query_embedding, top_k=5)
"""

import json
import uuid
import hashlib
import time
from typing import Optional, Dict, List, Any, Union
from dataclasses import dataclass
from enum import Enum

try:
    import chromadb
    from chromadb.config import Settings as ChromaSettings
    CHROMA_AVAILABLE = True
except ImportError:
    CHROMA_AVAILABLE = False

try:
    import pinecone
    PINECONE_AVAILABLE = True
except ImportError:
    PINECONE_AVAILABLE = False

try:
    import weaviate
    from weaviate.auth import AuthApiKey
    WEAVIATE_AVAILABLE = True
except ImportError:
    WEAVIATE_AVAILABLE = False

try:
    import qdrant_client
    from qdrant_client import QdrantClient
    from qdrant_client.models import Distance, VectorParams, PointStruct
    QDRANT_AVAILABLE = True
except ImportError:
    QDRANT_AVAILABLE = False

try:
    import pymilvus
    from pymilvus import connections, collection
    MILVUS_AVAILABLE = True
except ImportError:
    MILVUS_AVAILABLE = False

try:
    import psycopg2
    from pgvector.psycopg2 import Vector
    PGVECTOR_AVAILABLE = True
except ImportError:
    PGVECTOR_AVAILABLE = False

try:
    import redis
    REDIS_AVAILABLE = True
except ImportError:
    REDIS_AVAILABLE = False

try:
    import azure.search.documents
    from azure.core.credentials import AzureKeyCredential
    AZURE_SEARCH_AVAILABLE = True
except ImportError:
    AZURE_SEARCH_AVAILABLE = False

from vector_db_pool import (
    ConnectionPool, QueryCache, CircuitBreaker,
    get_pool, get_cache, get_breaker, health_check_all
)


class Backend(Enum):
    MEMORY = "memory"
    CHROMA = "chroma"
    PINECONE = "pinecone"
    WEAVIATE = "weaviate"
    QDRANT = "qdrant"
    MILVUS = "milvus"
    PGVECTOR = "pgvector"
    REDIS = "redis"
    AZURE = "azure"


@dataclass
class SearchResult:
    id: str
    score: float
    embedding: Optional[List[float]] = None
    metadata: Optional[Dict[str, Any]] = None


class VectorDBBridge:
    """
    Unified interface to vector databases.
    
    Features:
    - Connection pooling
    - Retry with exponential backoff
    - Circuit breaker
    - Query caching
    - Metrics tracking
    """

    def __init__(
        self,
        backend: str = "memory",
        collection: str = "default",
        host: str = "localhost",
        api_key: Optional[str] = None,
        dimensions: int = 384,
        metric: str = "cosine",
        enable_cache: bool = True,
        cache_ttl: float = 300.0,
        **kwargs
    ):
        self.backend_name = backend.lower()
        self.collection = collection
        self.host = host
        self.api_key = api_key
        self.dimensions = dimensions
        self.metric = metric
        self._client = None
        self._collection = None
        
        self._pool = get_pool(backend)
        self._cache = get_cache(backend) if enable_cache else None
        self._breaker = get_breaker(backend)
        
        self._init_backend(**kwargs)

    def _init_backend(self, **kwargs):
        """Initialize the appropriate backend."""

        if self.backend_name == "memory":
            self._init_memory_backend()
        elif self.backend_name == "chroma":
            self._init_chroma_backend(**kwargs)
        elif self.backend_name == "pinecone":
            self._init_pinecone_backend(**kwargs)
        elif self.backend_name == "weaviate":
            self._init_weaviate_backend(**kwargs)
        elif self.backend_name == "qdrant":
            self._init_qdrant_backend(**kwargs)
        elif self.backend_name == "milvus":
            self._init_milvus_backend(**kwargs)
        elif self.backend_name == "pgvector":
            self._init_pgvector_backend(**kwargs)
        elif self.backend_name == "redis":
            self._init_redis_backend(**kwargs)
        elif self.backend_name == "azure":
            self._init_azure_backend(**kwargs)
        else:
            raise ValueError(f"Unknown backend: {self.backend_name}")

    def _init_memory_backend(self):
        """In-memory fallback using pure Python."""
        self._memory_store = {}

    def _init_chroma_backend(self, persist_directory: str = "./chroma_data", **kwargs):
        """Initialize ChromaDB."""
        if not CHROMA_AVAILABLE:
            raise ImportError("chromadb not installed. Run: pip install chromadb")

        self._chroma_settings = ChromaSettings(
            persist_directory=persist_directory,
            anonymized_telemetry=False
        )

        if self.host and "http" in self.host:
            self._client = chromadb.HttpClient(host=self.host, settings=self._chroma_settings)
        else:
            self._client = chromadb.PersistentClient(path=self.host or persist_directory)

        self._collection = self._client.get_or_create_collection(
            name=self.collection,
            metadata={"hnsw:space": self.metric}
        )

    def _init_pinecone_backend(self, environment: str = "us-west1-gcp", **kwargs):
        """Initialize Pinecone."""
        if not PINECONE_AVAILABLE:
            raise ImportError("pinecone not installed. Run: pip install pinecone-client")

        if not self.api_key:
            raise ValueError("Pinecone requires api_key")

        pinecone.init(api_key=self.api_key, environment=environment)

        index = pinecone.Index(self.collection)
        self._client = index
        self._pinecone_index = self.collection

    def _init_weaviate_backend(self, **kwargs):
        """Initialize Weaviate."""
        if not WEAVIATE_AVAILABLE:
            raise ImportError("weaviate-client not installed. Run: pip install weaviate-client")

        auth_config = None
        if self.api_key:
            auth_config = AuthApiKey(api_key=self.api_key)

        self._client = weaviate.Client(
            url=self.host if self.host.startswith("http") else f"http://{self.host}",
            auth_client_secret=auth_config
        )

        if not self._client.schema.exists(self.collection):
            class_obj = {
                "class": self.collection,
                "vectorizer": "none",
                "moduleConfig": {
                    "text2vec-transformers": {
                        "vectorizeClassName": False
                    }
                }
            }
            self._client.schema.create_class(class_obj)

        self._collection = self._client.data_object

    def _init_qdrant_backend(self, **kwargs):
        """Initialize Qdrant."""
        if not QDRANT_AVAILABLE:
            raise ImportError("qdrant-client not installed. Run: pip install qdrant-client")

        if self.host:
            self._client = QdrantClient(url=self.host)
        else:
            self._client = QdrantClient(path="./qdrant_data")

        distance_map = {
            "cosine": Distance.COSINE,
            "euclidean": Distance.EUCLIDEAN,
            "dot": Distance.DOT
        }

        self._client.recreate_collection(
            collection_name=self.collection,
            vectors_config=VectorParams(
                size=self.dimensions,
                distance=distance_map.get(self.metric, Distance.COSINE)
            )
        )

    def _init_milvus_backend(self, **kwargs):
        """Initialize Milvus."""
        if not MILVUS_AVAILABLE:
            raise ImportError("pymilvus not installed. Run: pip install pymilvus")

        connections.connect(host=self.host or "localhost", port="19530")

        schema = {
            "fields": [
                {"name": "id", "type": "INT64", "is_primary": True},
                {"name": "embedding", "type": "FLOAT_VECTOR", "params": {"dim": self.dimensions}},
                {"name": "metadata", "type": "STRING"}
            ]
        }

        self._collection = f"Collection_{self.collection}"

    def _init_pgvector_backend(self, **kwargs):
        """Initialize pgvector (PostgreSQL vector extension)."""
        if not PGVECTOR_AVAILABLE:
            raise ImportError("pgvector not installed. Run: pip install pgvector")

        import os

        self._conn_params = {
            "host": kwargs.get("host", os.environ.get("PGHOST", "localhost")),
            "port": kwargs.get("port", os.environ.get("PGPORT", "5432")),
            "database": kwargs.get("database", os.environ.get("PGDATABASE", "postgres")),
            "user": kwargs.get("user", os.environ.get("PGUSER", "postgres")),
            "password": kwargs.get("password", os.environ.get("PGPASSWORD", ""))
        }

        self._table_name = kwargs.get("table", f"vector_{self.collection}")
        self._connection = None

    def _get_pgvector_connection(self):
        """Get or create PostgreSQL connection."""
        if self._connection is None:
            import psycopg2
            self._connection = psycopg2.connect(**self._conn_params)
        return self._connection

    def _init_redis_backend(self, **kwargs):
        """Initialize Redis with vector search."""
        if not REDIS_AVAILABLE:
            raise ImportError("redis not installed. Run: pip install redis")

        import os

        self._redis_params = {
            "host": kwargs.get("host", os.environ.get("REDIS_HOST", "localhost")),
            "port": kwargs.get("port", os.environ.get("REDIS_PORT", "6379")),
            "db": kwargs.get("db", 0),
            "password": kwargs.get("password", os.environ.get("REDIS_PASSWORD", None))
        }

        self._index_name = f"idx:{self.collection}"
        self._redis_client = None

    def _get_redis_client(self):
        """Get or create Redis client."""
        if self._redis_client is None:
            self._redis_client = redis.Redis(**self._redis_params)
        return self._redis_client

    def _init_azure_backend(self, **kwargs):
        """Initialize Azure AI Search."""
        if not AZURE_SEARCH_AVAILABLE:
            raise ImportError("azure-search-documents not installed. Run: pip install azure-search-documents")

        self._search_endpoint = kwargs.get("endpoint")
        self._search_key = kwargs.get("api_key")
        self._index_name = kwargs.get("index_name", self.collection)

        if not self._search_endpoint or not self._search_key:
            raise ValueError("Azure AI Search requires endpoint and api_key")

        self._search_client = azure.search.documents.SearchClient(
            endpoint=self._search_endpoint,
            index_name=self._index_name,
            credential=AzureKeyCredential(self._search_key)
        )

    def _with_circuit_breaker(self, operation):
        """Execute operation with circuit breaker protection."""
        with self._breaker:
            return operation()

    def _with_retry(self, operation):
        """Execute operation with retry logic."""
        return self._pool.execute_with_retry(operation)

    def add(
        self,
        doc_id: str,
        embedding: List[float],
        metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Add a single document to the database."""
        return self._with_circuit_breaker(
            lambda: self._add_impl(doc_id, embedding, metadata)
        )

    def _add_impl(self, doc_id, embedding, metadata):
        """Internal add implementation with retry."""
        def operation():
            if self.backend_name == "memory":
                return self._add_memory(doc_id, embedding, metadata)
            elif self.backend_name == "chroma":
                return self._add_chroma(doc_id, embedding, metadata)
            elif self.backend_name == "pinecone":
                return self._add_pinecone(doc_id, embedding, metadata)
            elif self.backend_name == "weaviate":
                return self._add_weaviate(doc_id, embedding, metadata)
            elif self.backend_name == "qdrant":
                return self._add_qdrant(doc_id, embedding, metadata)
            return False
        
        return self._with_retry(operation)

    def _add_memory(self, doc_id, embedding, metadata):
        self._memory_store[doc_id] = (embedding, metadata or {})
        return True

    def _add_chroma(self, doc_id, embedding, metadata):
        self._collection.add(
            ids=[doc_id],
            embeddings=[embedding],
            metadatas=[metadata or {}]
        )
        return True

    def _add_pinecone(self, doc_id, embedding, metadata):
        self._client.upsert(
            vectors=[{
                "id": doc_id,
                "values": embedding,
                "metadata": metadata or {}
            }]
        )
        return True

    def _add_weaviate(self, doc_id, embedding, metadata):
        self._collection.with_data_object(
            data_object=metadata or {},
            vector=embedding,
            class_name=self.collection,
            uuid=doc_id
        )
        return True

    def _add_qdrant(self, doc_id, embedding, metadata):
        self._client.upsert(
            collection_name=self.collection,
            points=[PointStruct(
                id=doc_id,
                vector=embedding,
                payload=metadata or {}
            )]
        )
        return True

    def _add_milvus(self, doc_id, embedding, metadata):
        import json
        from pymilvus import CollectionSchema, FieldSchema, DataType

        self._client.insert(
            collection_name=self._collection,
            records=[embedding],
            ids=[doc_id],
            payloads=[json.dumps(metadata or {})]
        )
        return True

    def _add_pgvector(self, doc_id, embedding, metadata):
        import json
        conn = self._get_pgvector_connection()
        with conn.cursor() as cur:
            # Insert vector and metadata
            cur.execute(
                f"INSERT INTO {self._table_name} (id, embedding, metadata) VALUES (%s, %s, %s) ON CONFLICT (id) DO UPDATE",
                (doc_id, embedding, json.dumps(metadata or {}))
            )
            conn.commit()
        return True

    def _add_redis(self, doc_id, embedding, metadata):
        import json
        client = self._get_redis_client()
        key = f"doc:{doc_id}"
        client.hset(key, mapping={
            "embedding": json.dumps(embedding),
            "metadata": json.dumps(metadata or {}),
            "vector": json.dumps(embedding)
        })
        # Add to index
        client.sadd(f"{self._index_name}:ids", doc_id)
        return True

    def _add_azure(self, doc_id, embedding, metadata):
        document = {
            "id": doc_id,
            "embedding": embedding,
            "@search.action": "upload"
        }
        document.update(metadata or {})
        self._search_client.upload_documents(documents=[document])
        return True

    def add_batch(
        self,
        documents: List[Dict[str, Any]],
        embeddings: Optional[List[List[float]]] = None
    ) -> int:
        """Add multiple documents efficiently."""
        return self._with_circuit_breaker(
            lambda: self._add_batch_impl(documents, embeddings)
        )

    def _add_batch_impl(self, documents, embeddings):
        def operation():
            if not documents:
                return 0
            
            if embeddings is None:
                embeddings = [doc.get("embedding", []) for doc in documents]

            ids = [doc.get("id", str(uuid.uuid4())) for doc in documents]
            metadatas = [doc.get("metadata", {}) for doc in documents]

            count = 0
            for i, (doc_id, embedding, metadata) in enumerate(zip(ids, embeddings, metadatas)):
                if self._add_impl(doc_id, embedding, metadata):
                    count += 1

            return count
        
        return self._with_retry(operation)

    def search(
        self,
        query_embedding: List[float],
        top_k: int = 10,
        filter: Optional[Dict[str, Any]] = None,
        include_embeddings: bool = False,
        use_cache: bool = True
    ) -> List[SearchResult]:
        """Search for similar documents."""
        
        # Try cache first
        if use_cache and self._cache:
            cached = self._cache.get(query_embedding, top_k, filter)
            if cached is not None:
                return cached

        def operation():
            if self.backend_name == "memory":
                results = self._search_memory(query_embedding, top_k)
            elif self.backend_name == "chroma":
                results = self._search_chroma(query_embedding, top_k, include_embeddings)
            elif self.backend_name == "pinecone":
                results = self._search_pinecone(query_embedding, top_k, filter)
            elif self.backend_name == "weaviate":
                results = self._search_weaviate(query_embedding, top_k, include_embeddings)
            elif self.backend_name == "qdrant":
                results = self._search_qdrant(query_embedding, top_k, include_embeddings)
            else:
                results = []

            # Cache results
            if use_cache and self._cache:
                self._cache.set(query_embedding, top_k, filter, results)

            return results

        try:
            return self._with_circuit_breaker(operation)
        except Exception as e:
            # Invalidate cache on error
            if self._cache:
                self._cache.invalidate(query_embedding, top_k, filter)
            raise

    def _search_memory(self, query: List[float], top_k: int) -> List[SearchResult]:
        """Search in-memory store."""
        all_items = list(self._memory_store.items())
        scored = []

        for doc_id, (embedding, metadata) in all_items.items():
            score = self._cosine_similarity(query, embedding)
            scored.append((doc_id, score, metadata))

        scored.sort(key=lambda x: x[1], reverse=True)
        return [
            SearchResult(id=doc_id, score=score, metadata=metadata)
            for doc_id, score, metadata in scored[:top_k]
        ]

    def _search_chroma(self, query: List[float], top_k: int, include_embeddings: bool) -> List[SearchResult]:
        """Search ChromaDB."""
        results = self._collection.query(
            query_embeddings=[query],
            n_results=top_k,
            include=["metadatas", "distances", "embeddings" if include_embeddings else []]
        )

        output = []
        for i in range(len(results.get("ids", [[]])[0])):
            embedding = results["embeddings"][0][i] if include_embeddings and results.get("embeddings") else None
            distance = results["distances"][0][i] if results.get("distances") else 0.0
            score = 1.0 - distance

            output.append(SearchResult(
                id=results["ids"][0][i],
                score=score,
                embedding=embedding,
                metadata=results["metadatas"][0][i] if results.get("metadatas") else {}
            ))

        return output

    def _search_pinecone(self, query: List[float], top_k: int, filter: Dict = None) -> List[SearchResult]:
        """Search Pinecone."""
        search_params = {
            "top_k": top_k,
            "vector": query,
            "include_metadata": True
        }

        if filter:
            search_params["filter"] = filter

        results = self._client.query(**search_params)

        return [
            SearchResult(
                id=match["id"],
                score=match["score"],
                metadata=match.get("metadata", {})
            )
            for match in results.get("matches", [])
        ]

    def _search_weaviate(self, query: List[float], top_k: int, include_embeddings: bool) -> List[SearchResult]:
        """Search Weaviate."""
        near_vector = {"vector": query}

        query_obj = self._client.query.get(
            class_name=self.collection,
            properties=["*"]
        ).with_near_vector(near_vector).with_limit(top_k)

        if include_embeddings:
            query_obj = query_obj.with_additional(["vector"])

        results = query_obj.do()

        output = []
        if results.get("data", {}).get("Get"):
            for item in results["data"]["Get"].get(self.collection, []):
                output.append(SearchResult(
                    id=item.get("_additional", {}).get("id", ""),
                    score=item.get("_additional", {}).get("certainty", 0.0),
                    embedding=item.get("_additional", {}).get("vector") if include_embeddings else None,
                    metadata={k: v for k, v in item.items() if k != "_additional"}
                ))

        return output

    def _search_qdrant(self, query: List[float], top_k: int, include_embeddings: bool) -> List[SearchResult]:
        """Search Qdrant."""
        results = self._client.search(
            collection_name=self.collection,
            query_vector=query,
            limit=top_k
        )

        return [
            SearchResult(
                id=hit.id,
                score=hit.score,
                embedding=hit.vector if include_embeddings and hasattr(hit, 'vector') else None,
                metadata=hit.payload or {}
            )
            for hit in results
        ]

    def _search_milvus(self, query: List[float], top_k: int, include_embeddings: bool) -> List[SearchResult]:
        """Search Milvus."""
        results = self._client.search(
            collection_name=self._collection,
            query_records=[query],
            top_k=top_k
        )

        output = []
        for hits in results:
            for hit in hits:
                output.append(SearchResult(
                    id=str(hit.id),
                    score=hit.score,
                    embedding=query if include_embeddings else None,
                    metadata={}
                ))
        return output

    def _search_pgvector(self, query: List[float], top_k: int, include_embeddings: bool) -> List[SearchResult]:
        """Search pgvector."""
        import json
        conn = self._get_pgvector_connection()
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT id, embedding, metadata FROM {self._table_name} ORDER BY embedding <-> %s LIMIT %s",
                (query, top_k)
            )
            rows = cur.fetchall()
            return [
                SearchResult(
                    id=row[0],
                    score=1.0 - self._cosine_similarity(query, row[1]),
                    embedding=row[1] if include_embeddings else None,
                    metadata=json.loads(row[2]) if row[2] else {}
                )
                for row in rows
            ]

    def _search_redis(self, query: List[float], top_k: int, include_embeddings: bool) -> List[SearchResult]:
        """Search Redis using brute force (for small datasets)."""
        import json
        client = self._get_redis_client()
        all_ids = list(client.smembers(f"{self._index_name}:ids"))

        scored = []
        for doc_id in all_ids:
            key = f"doc:{doc_id}"
            data = client.hgetall(key)
            if data:
                embedding = json.loads(data.get(b"embedding", b"[]"))
                score = self._cosine_similarity(query, embedding)
                scored.append((doc_id, score, json.loads(data.get(b"metadata", b"{}"))))

        scored.sort(key=lambda x: x[1], reverse=True)
        return [
            SearchResult(id=doc_id, score=score, metadata=metadata)
            for doc_id, score, metadata in scored[:top_k]
        ]

    def _search_azure(self, query: List[float], top_k: int, include_embeddings: bool) -> List[SearchResult]:
        """Search Azure AI Search."""
        from azure.search.documents.models import VectorQuery

        results = self._search_client.search(
            search_text=None,
            vector_queries=[VectorQuery(vector=query, k=top_k, fields="embedding")],
            select=["id", "metadata"] if not include_embeddings else ["id", "embedding", "metadata"]
        )

        return [
            SearchResult(
                id=doc["id"],
                score=doc.get("@search.score", 0.0),
                embedding=doc.get("embedding") if include_embeddings else None,
                metadata=doc.get("metadata", {})
            )
            for doc in results
        ]

    def get(self, doc_id: str) -> Optional[Dict[str, Any]]:
        """Get a document by ID."""
        import json

        if self.backend_name == "chroma":
            result = self._collection.get(ids=[doc_id])
            if result["ids"]:
                return {
                    "id": doc_id,
                    "embedding": result["embeddings"][0] if result.get("embeddings") else None,
                    "metadata": result["metadatas"][0] if result.get("metadatas") else {}
                }

        elif self.backend_name == "pinecone":
            results = self._client.fetch(ids=[doc_id])
            if results.get("vectors", {}):
                vec = results["vectors"][doc_id]
                return {
                    "id": doc_id,
                    "embedding": vec.get("values"),
                    "metadata": vec.get("metadata", {})
                }

        elif self.backend_name == "weaviate":
            try:
                result = self._client.data_object.get_by_id(doc_id, class_name=self.collection)
                if result:
                    return {
                        "id": doc_id,
                        "embedding": result.get("vector"),
                        "metadata": result.get("properties", {})
                    }
            except:
                pass

        elif self.backend_name == "qdrant":
            points = self._client.retrieve(collection_name=self.collection, ids=[doc_id])
            if points:
                point = points[0]
                return {
                    "id": point.id,
                    "embedding": point.vector,
                    "metadata": point.payload or {}
                }

        elif self.backend_name == "memory":
            if doc_id in self._memory_store:
                embedding, metadata = self._memory_store[doc_id]
                return {"id": doc_id, "embedding": embedding, "metadata": metadata}

        elif self.backend_name == "pgvector":
            conn = self._get_pgvector_connection()
            with conn.cursor() as cur:
                cur.execute(
                    f"SELECT id, embedding, metadata FROM {self._table_name} WHERE id = %s",
                    (doc_id,)
                )
                row = cur.fetchone()
                if row:
                    return {
                        "id": row[0],
                        "embedding": row[1],
                        "metadata": json.loads(row[2]) if row[2] else {}
                    }

        elif self.backend_name == "redis":
            client = self._get_redis_client()
            key = f"doc:{doc_id}"
            data = client.hgetall(key)
            if data:
                return {
                    "id": doc_id,
                    "embedding": json.loads(data.get(b"embedding", b"[]")),
                    "metadata": json.loads(data.get(b"metadata", b"{}"))
                }

        elif self.backend_name == "azure":
            try:
                doc = self._search_client.get_document(key=doc_id)
                return {
                    "id": doc["id"],
                    "embedding": doc.get("embedding"),
                    "metadata": {k: v for k, v in doc.items() if k not in ["id", "embedding"]}
                }
            except:
                pass

        return None

    def delete(self, doc_id: str) -> bool:
        """Delete a document by ID."""
        if self.backend_name == "chroma":
            self._collection.delete(ids=[doc_id])
            return True

        elif self.backend_name == "pinecone":
            self._client.delete(ids=[doc_id])
            return True

        elif self.backend_name == "weaviate":
            try:
                self._client.data_object.delete(doc_id, class_name=self.collection)
                return True
            except:
                return False

        elif self.backend_name == "qdrant":
            self._client.delete(collection_name=self.collection, points_selector=[doc_id])
            return True

        elif self.backend_name == "memory":
            if doc_id in self._memory_store:
                del self._memory_store[doc_id]
                return True

        elif self.backend_name == "pgvector":
            import psycopg2
            conn = self._get_pgvector_connection()
            with conn.cursor() as cur:
                cur.execute(f"DELETE FROM {self._table_name} WHERE id = %s", (doc_id,))
                conn.commit()
            return True

        elif self.backend_name == "redis":
            client = self._get_redis_client()
            client.delete(f"doc:{doc_id}")
            client.srem(f"{self._index_name}:ids", doc_id)
            return True

        elif self.backend_name == "azure":
            try:
                self._search_client.delete_documents(documents=[{"id": doc_id}])
                return True
            except:
                return False

        return False

    def update_metadata(self, doc_id: str, metadata: Dict) -> bool:
        """Update document metadata."""
        import json

        if self.backend_name == "chroma":
            self._collection.update(ids=[doc_id], metadatas=[metadata])
            return True

        elif self.backend_name == "pinecone":
            self._client.upsert([{
                "id": doc_id,
                "values": None,
                "metadata": metadata
            }])
            return True

        elif self.backend_name == "weaviate":
            try:
                self._client.data_object.update(doc_id, class_name=self.collection, data_object=metadata)
                return True
            except:
                return False

        elif self.backend_name == "qdrant":
            self._client.set_payload(collection_name=self.collection, payload=metadata, points=[doc_id])
            return True

        elif self.backend_name == "memory":
            if doc_id in self._memory_store:
                embedding, _ = self._memory_store[doc_id]
                self._memory_store[doc_id] = (embedding, metadata)
                return True

        elif self.backend_name == "pgvector":
            conn = self._get_pgvector_connection()
            with conn.cursor() as cur:
                cur.execute(
                    f"UPDATE {self._table_name} SET metadata = %s WHERE id = %s",
                    (json.dumps(metadata), doc_id)
                )
                conn.commit()
            return True

        elif self.backend_name == "redis":
            client = self._get_redis_client()
            client.hset(f"doc:{doc_id}", "metadata", json.dumps(metadata))
            return True

        elif self.backend_name == "azure":
            try:
                doc = self._search_client.get_document(key=doc_id)
                doc.update(metadata)
                self._search_client.merge_or_upload_documents(documents=[doc])
                return True
            except:
                return False

        return False

    def count(self) -> int:
        """Get the number of documents."""
        import json

        if self.backend_name == "chroma":
            return self._collection.count()

        elif self.backend_name == "pinecone":
            stats = self._client.describe_index_stats()
            return stats.get("total_vector_count", 0)

        elif self.backend_name == "qdrant":
            return self._client.count(collection_name=self.collection).count

        elif self.backend_name == "memory":
            return len(self._memory_store)

        elif self.backend_name == "pgvector":
            conn = self._get_pgvector_connection()
            with conn.cursor() as cur:
                cur.execute(f"SELECT COUNT(*) FROM {self._table_name}")
                return cur.fetchone()[0]

        elif self.backend_name == "redis":
            client = self._get_redis_client()
            return client.scard(f"{self._index_name}:ids")

        elif self.backend_name == "azure":
            try:
                return self._search_client.get_document_count()
            except:
                return 0

        return 0

    def stats(self) -> Dict[str, Any]:
        """Get database statistics."""
        return {
            "backend": self.backend_name,
            "count": self.count(),
            "dimensions": self.dimensions,
            "metric": self.metric
        }

    def health(self) -> Dict[str, Any]:
        """Get health status including circuit breaker and pool stats."""
        return {
            "circuit_breaker": self._breaker.stats(),
            "pool": self._pool.health_check(),
            "cache": self._cache.stats() if self._cache else None
        }

    def close(self):
        """Close connections and cleanup."""
        if self.backend_name == "milvus":
            connections.disconnect()
        elif self.backend_name == "pgvector":
            if self._connection:
                self._connection.close()
        elif self.backend_name == "redis":
            if self._redis_client:
                self._redis_client.close()

    @staticmethod
    def _cosine_similarity(a: List[float], b: List[float]) -> float:
        """Compute cosine similarity between two vectors."""
        import math
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = math.sqrt(sum(x * x for x in a))
        norm_b = math.sqrt(sum(x * x for x in b))
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return dot / (norm_a * norm_b)

    @staticmethod
    def available_backends() -> Dict[str, bool]:
        """Check which backends are available."""
        return {
            "memory": True,
            "chroma": CHROMA_AVAILABLE,
            "pinecone": PINECONE_AVAILABLE,
            "weaviate": WEAVIATE_AVAILABLE,
            "qdrant": QDRANT_AVAILABLE,
            "milvus": MILVUS_AVAILABLE,
            "pgvector": PGVECTOR_AVAILABLE,
            "redis": REDIS_AVAILABLE,
            "azure": AZURE_SEARCH_AVAILABLE
        }


# Bridge protocol for Zixir Elixir integration
PROTOCOL = {
    "version": "3.0",
    "operations": [
        "create",
        "add",
        "add_batch",
        "search",
        "get",
        "delete",
        "update",
        "count",
        "stats",
        "health",
        "clear_cache",
        "close"
    ],
    "backends": [
        "memory", "chroma", "pinecone", "weaviate", 
        "qdrant", "milvus", "pgvector", "redis", "azure"
    ],
    "features": {
        "connection_pooling": True,
        "retry_logic": True,
        "circuit_breaker": True,
        "query_cache": True,
        "metrics": True
    }
}
