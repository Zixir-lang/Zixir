"""
ODBC Bridge for Zixir - Universal SQL Database Access

Provides ODBC connectivity via pyodbc with connection pooling,
query optimization, and automatic type conversion.
"""

import os
import json
import threading
import uuid
import hashlib
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field
from datetime import datetime, date
from decimal import Decimal
import logging

try:
    import pyodbc
    PYODBC_AVAILABLE = True
except ImportError:
    PYODBC_AVAILABLE = False

logger = logging.getLogger(__name__)


@dataclass
class ConnectionConfig:
    """ODBC connection configuration."""
    dsn: Optional[str] = None
    connection_string: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None
    host: Optional[str] = None
    database: Optional[str] = None
    driver: Optional[str] = None
    port: Optional[int] = None
    autocommit: bool = False
    timeout: int = 30
    max_pool_size: int = 10
    pool_timeout: int = 30


@dataclass
class QueryResult:
    """Query execution result."""
    rows: List[Dict[str, Any]]
    columns: List[str]
    row_count: int
    affected_rows: int = 0


class ConnectionPool:
    """ODBC connection pool manager."""

    def __init__(self, config: ConnectionConfig, pool_id: str):
        self.config = config
        self.pool_id = pool_id
        self._pool: List[Any] = []
        self._lock = threading.Lock()
        self._active = 0

    def get_connection(self) -> 'PooledConnection':
        """Acquire connection from pool."""
        with self._lock:
            if self._pool:
                conn = self._pool.pop()
            else:
                if self._active >= self.config.max_pool_size:
                    raise PoolExhaustedError(
                        f"Connection pool exhausted. Active: {self._active}, Max: {self.config.max_pool_size}"
                    )
                conn = self._create_connection()
                self._active += 1
            return PooledConnection(conn, self)

    def return_connection(self, conn: 'PooledConnection'):
        """Return connection to pool."""
        with self._lock:
            if self._active > 0:
                self._pool.append(conn)

    def _create_connection(self) -> Any:
        """Create new ODBC connection."""
        if self.config.connection_string:
            conn_str = self.config.connection_string
        elif self.config.dsn:
            conn_str = f"DSN={self.config.dsn}"
        else:
            parts = []
            if self.config.driver:
                parts.append(f"DRIVER={self.config.driver}")
            if self.config.host:
                parts.append(f"SERVER={self.config.host}")
            if self.config.database:
                parts.append(f"DATABASE={self.config.database}")
            if self.config.username:
                parts.append(f"UID={self.config.username}")
            if self.config.password:
                parts.append(f"PWD={self.config.password}")
            if self.config.port:
                parts.append(f"PORT={self.config.port}")
            conn_str = ";".join(parts)

        try:
            conn = pyodbc.connect(conn_str, timeout=self.config.timeout)
            conn.autocommit = self.config.autocommit
            return conn
        except Exception as e:
            logger.error(f"Failed to create ODBC connection: {e}")
            raise

    @property
    def active_count(self) -> int:
        """Get number of active connections."""
        with self._lock:
            return self._active

    @property
    def available_count(self) -> int:
        """Get number of available connections in pool."""
        with self._lock:
            return len(self._pool)


class PooledConnection:
    """Wrapper for pooled ODBC connection."""

    def __init__(self, conn: Any, pool: ConnectionPool):
        self._conn = conn
        self._pool = pool
        self._closed = False

    @property
    def cursor(self) -> 'TypeConvertingCursor':
        """Get cursor with automatic type conversion."""
        cursor = self._conn.cursor()
        return TypeConvertingCursor(cursor)

    def close(self):
        """Return to pool instead of closing."""
        if not self._closed:
            self._pool.return_connection(self)
            self._closed = True

    def commit(self):
        """Commit transaction."""
        self._conn.commit()

    def rollback(self):
        """Rollback transaction."""
        self._conn.rollback()

    @property
    def connected(self) -> bool:
        """Check if connection is still connected."""
        try:
            self._conn.cursor()
            return True
        except:
            return False


class TypeConvertingCursor:
    """Cursor with automatic type conversion."""

    TYPE_MAP = {
        pyodbc.SQL_CHAR: str,
        pyodbc.SQL_VARCHAR: str,
        pyodbc.SQL_LONGVARCHAR: str,
        pyodbc.SQL_DECIMAL: Decimal,
        pyodbc.SQL_NUMERIC: Decimal,
        pyodbc.SQL_INTEGER: int,
        pyodbc.SQL_SMALLINT: int,
        pyodbc.SQL_FLOAT: float,
        pyodbc.SQL_REAL: float,
        pyodbc.SQL_DOUBLE: float,
        pyodbc.SQL_DATETIME: datetime,
        pyodbc.SQL_DATE: date,
        pyodbc.SQL_TIME: datetime,
        pyodbc.SQL_TIMESTAMP: datetime,
        pyodbc.SQL_BIT: bool,
    }

    def __init__(self, cursor: Any):
        self._cursor = cursor
        self._description = None

    def execute(self, sql: str, params: Optional[List[Any]] = None):
        """Execute query with parameter substitution."""
        try:
            if params:
                processed_params = [self._convert_param(p) for p in params]
            else:
                processed_params = None

            self._cursor.execute(sql, processed_params or [])
            self._description = self._cursor.description
            return self
        except Exception as e:
            logger.error(f"Execute failed: {e}")
            raise

    def fetchone(self) -> Optional[Dict[str, Any]]:
        """Fetch single row."""
        row = self._cursor.fetchone()
        if row:
            return self._convert_row(row)
        return None

    def fetchall(self) -> List[Dict[str, Any]]:
        """Fetch all rows."""
        rows = self._cursor.fetchall()
        return [self._convert_row(row) for row in rows]

    def fetchmany(self, size: Optional[int] = None) -> List[Dict[str, Any]]:
        """Fetch many rows."""
        if size:
            rows = self._cursor.fetchmany(size)
        else:
            rows = self._cursor.fetchmany()
        return [self._convert_row(row) for row in rows]

    @property
    def description(self) -> Optional[List[tuple]]:
        """Get column descriptions."""
        return self._description

    @property
    def rowcount(self) -> int:
        """Get affected row count."""
        return self._cursor.rowcount

    def _convert_param(self, param: Any) -> Any:
        """Convert parameter to database-compatible type."""
        if param is None:
            return None
        if isinstance(param, (datetime, date)):
            return param.isoformat()
        if isinstance(param, Decimal):
            return float(param)
        if isinstance(param, (list, dict)):
            return json.dumps(param)
        if isinstance(param, bool):
            return 1 if param else 0
        return param

    def _convert_row(self, row) -> Dict[str, Any]:
        """Convert row to dict with column names."""
        if not self._description:
            return dict(enumerate(row))

        converted = {}
        for i, (col, val) in enumerate(zip([d[0] for d in self._description], row)):
            if val is None:
                converted[col] = None
            elif isinstance(val, bytes):
                try:
                    converted[col] = val.decode('utf-8')
                except:
                    try:
                        converted[col] = val.decode('latin-1')
                    except:
                        converted[col] = val.hex()
            else:
                converted[col] = val
        return converted


class PoolExhaustedError(Exception):
    """Raised when connection pool is exhausted."""
    pass


class ODBCBridge:
    """
    Main ODBC Bridge for Zixir.

    Provides:
    - Connection pooling
    - Query execution
    - Transaction management
    - Metadata extraction
    """

    def __init__(self):
        self._pools: Dict[str, ConnectionPool] = {}
        self._lock = threading.Lock()

    def connect(self, config: Dict) -> Dict:
        """
        Create a new ODBC connection pool.

        Args:
            config: Connection configuration dict

        Returns:
            {"status": "ok", "pool_id": "...", "config": {...}}
        """
        if not PYODBC_AVAILABLE:
            return {
                "status": "error",
                "message": "pyodbc not installed. Run: pip install pyodbc"
            }

        try:
            conn_config = ConnectionConfig(
                dsn=config.get("dsn"),
                connection_string=config.get("connection_string"),
                username=config.get("username"),
                password=config.get("password"),
                host=config.get("host"),
                database=config.get("database"),
                driver=config.get("driver"),
                port=config.get("port"),
                autocommit=config.get("autocommit", False),
                timeout=config.get("timeout", 30),
                max_pool_size=config.get("max_pool_size", 10)
            )

            pool_id = f"odbc_{uuid.uuid4().hex[:12]}"

            with self._lock:
                self._pools[pool_id] = ConnectionPool(conn_config, pool_id)

            return {
                "status": "ok",
                "pool_id": pool_id,
                "config": {
                    "driver": conn_config.driver or "default",
                    "database": conn_config.database,
                    "host": conn_config.host or "localhost"
                }
            }

        except Exception as e:
            logger.error(f"ODBC connect failed: {e}")
            return {
                "status": "error",
                "message": str(e)
            }

    def query(self, pool_id: str, sql: str, params: Optional[List[Any]] = None) -> Dict:
        """Execute a SELECT query."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            with pool.get_connection() as conn:
                cursor = conn.cursor
                cursor.execute(sql, params or [])

                rows = cursor.fetchall()
                columns = [desc[0] for desc in cursor.description] if cursor.description else []

                return {
                    "status": "ok",
                    "columns": columns,
                    "rows": rows,
                    "row_count": len(rows)
                }

        except Exception as e:
            logger.error(f"ODBC query failed: {e}")
            return {
                "status": "error",
                "message": str(e),
                "sql": sql[:200] if sql else ""
            }

    def execute(self, pool_id: str, sql: str, params: Optional[List[Any]] = None) -> Dict:
        """Execute INSERT/UPDATE/DELETE."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            with pool.get_connection() as conn:
                cursor = conn.cursor
                cursor.execute(sql, params or [])
                conn.commit()

                return {
                    "status": "ok",
                    "affected_rows": cursor.rowcount
                }

        except Exception as e:
            logger.error(f"ODBC execute failed: {e}")
            return {
                "status": "error",
                "message": str(e),
                "sql": sql[:200] if sql else ""
            }

    def fetch(self, pool_id: str, sql: str, limit: int = 1000, offset: int = 0) -> Dict:
        """Execute query with pagination."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            paginated_sql = f"{sql} LIMIT {limit} OFFSET {offset}"

            with pool.get_connection() as conn:
                cursor = conn.cursor
                cursor.execute(paginated_sql)

                rows = cursor.fetchall()
                columns = [desc[0] for desc in cursor.description] if cursor.description else []

                return {
                    "status": "ok",
                    "columns": columns,
                    "rows": rows,
                    "row_count": len(rows),
                    "has_more": len(rows) == limit
                }

        except Exception as e:
            logger.error(f"ODBC fetch failed: {e}")
            return {
                "status": "error",
                "message": str(e)
            }

    def transaction(self, pool_id: str, operations: List[Dict]) -> Dict:
        """Execute multiple operations in a transaction."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            with pool.get_connection() as conn:
                results = []

                for op in operations:
                    sql = op.get("sql", "")
                    params = op.get("params", [])

                    cursor = conn.cursor
                    cursor.execute(sql, params)
                    results.append({
                        "sql": sql[:50],
                        "affected_rows": cursor.rowcount
                    })

                conn.commit()
                return {
                    "status": "ok",
                    "results": results
                }

        except Exception as e:
            logger.error(f"ODBC transaction failed: {e}")
            return {
                "status": "error",
                "message": str(e)
            }

    def disconnect(self, pool_id: str) -> Dict:
        """Close connection pool."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        with self._lock:
            if pool_id in self._pools:
                pool = self._pools[pool_id]
                with pool._lock:
                    for conn in pool._pool:
                        try:
                            conn.close()
                        except:
                            pass
                    pool._pool.clear()
                    pool._active = 0
                del self._pools[pool_id]

        return {"status": "ok"}

    def tables(self, pool_id: str, schema: Optional[str] = None) -> Dict:
        """Get list of tables."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            with pool.get_connection() as conn:
                cursor = conn.cursor

                if schema:
                    query = """
                    SELECT TABLE_NAME, TABLE_TYPE, TABLE_SCHEMA
                    FROM INFORMATION_SCHEMA.TABLES
                    WHERE TABLE_SCHEMA = ?
                    ORDER BY TABLE_NAME
                    """
                    cursor.execute(query, [schema])
                else:
                    query = """
                    SELECT TABLE_NAME, TABLE_TYPE, TABLE_SCHEMA
                    FROM INFORMATION_SCHEMA.TABLES
                    ORDER BY TABLE_NAME
                    """
                    cursor.execute(query)

                rows = cursor.fetchall()
                tables = [
                    {
                        "name": row[0],
                        "type": row[1],
                        "schema": row[2]
                    }
                    for row in rows
                ]

                return {
                    "status": "ok",
                    "tables": tables
                }

        except Exception as e:
            logger.error(f"ODBC tables failed: {e}")
            return {
                "status": "error",
                "message": str(e)
            }

    def columns(self, pool_id: str, table_name: str, schema: Optional[str] = None) -> Dict:
        """Get column information for a table."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            with pool.get_connection() as conn:
                cursor = conn.cursor

                if schema:
                    query = """
                    SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, ORDINAL_POSITION
                    FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_NAME = ? AND TABLE_SCHEMA = ?
                    ORDER BY ORDINAL_POSITION
                    """
                    cursor.execute(query, [table_name, schema])
                else:
                    query = """
                    SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, ORDINAL_POSITION
                    FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_NAME = ?
                    ORDER BY ORDINAL_POSITION
                    """
                    cursor.execute(query, [table_name])

                rows = cursor.fetchall()
                columns = [
                    {
                        "name": row[0],
                        "type": row[1],
                        "nullable": row[2] == "YES",
                        "default": row[3],
                        "ordinal": row[4]
                    }
                    for row in rows
                ]

                return {
                    "status": "ok",
                    "table": table_name,
                    "columns": columns
                }

        except Exception as e:
            logger.error(f"ODBC columns failed: {e}")
            return {
                "status": "error",
                "message": str(e)
            }

    def health(self, pool_id: str) -> Dict:
        """Check connection pool health."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        return {
            "status": "ok",
            "pool_id": pool_id,
            "pool_size": len(pool._pool),
            "active_connections": pool.active_count,
            "max_size": pool.config.max_pool_size
        }

    def execute_many(self, pool_id: str, sql: str, params_list: List[List[Any]]) -> Dict:
        """Execute the same SQL with multiple parameter sets."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            with pool.get_connection() as conn:
                cursor = conn.cursor
                total_affected = 0

                for params in params_list:
                    cursor.execute(sql, params)
                    total_affected += cursor.rowcount

                conn.commit()

                return {
                    "status": "ok",
                    "affected_rows": total_affected,
                    "batches": len(params_list)
                }

        except Exception as e:
            logger.error(f"ODBC execute_many failed: {e}")
            return {
                "status": "error",
                "message": str(e)
            }

    def ping(self, pool_id: str) -> Dict:
        """Check if connection is alive."""
        if pool_id not in self._pools:
            return {"status": "error", "message": "Unknown pool"}

        pool = self._pools[pool_id]

        try:
            with pool.get_connection() as conn:
                cursor = conn.cursor
                cursor.execute("SELECT 1")
                cursor.fetchone()
                return {"status": "ok", "message": "Connection alive"}

        except Exception as e:
            logger.error(f"ODBC ping failed: {e}")
            return {
                "status": "error",
                "message": str(e)
            }


odbc_bridge = ODBCBridge()
