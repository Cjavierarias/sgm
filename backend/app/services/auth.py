"""
Servicios de autenticación: JWT y hashing de contraseñas.

Funciones incluidas:
- `create_access_token(data, expires_delta)` -> str
- `verify_token(token)` -> dict (lanza HTTPException si inválido)
- `get_password_hash(password)` -> str
- `verify_password(plain, hashed)` -> bool

Usamos `python-jose` para JWT y `passlib[bcrypt]` para hashing.
Comentarios orientados a principiantes están incluidos.
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

from dotenv import load_dotenv
from fastapi import HTTPException, status
from jose import JWTError, jwt
import bcrypt


# Cargar variables de entorno (opcional en producción si ya están definidas)
load_dotenv()


# Configuración: puedes sobrescribir con variables de entorno
SECRET_KEY: str = os.getenv("SECRET_KEY", "changeme-in-dev")
ALGORITHM: str = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "60"))


def get_password_hash(password: str) -> str:
    """
    Hashea una contraseña plain-text usando bcrypt.

    - Nunca guardes contraseñas en texto plano en la base de datos.
    - `passlib` maneja salting y rounds por detrás.
    """
    if not password:
        raise ValueError("La contraseña no puede estar vacía")
    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verifica una contraseña plain contra su hash almacenado."""
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
    except Exception:
        # Cualquier error en verificación se considera fallo de autenticación
        return False


def create_access_token(data: Dict[str, Any], expires_delta: Optional[timedelta] = None) -> str:
    """
    Crea un JWT con la información en `data` y expiración opcional.

    - `data` típicamente contiene identificadores como `sub` (subject) o `user_id`.
    - `expires_delta` permite definir cuánto tiempo vivirá el token.
    """
    to_encode = data.copy()

    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)

    # JWT exp debe ser un timestamp UTC
    to_encode.update({"exp": expire})

    token = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return token


def verify_token(token: str) -> Dict[str, Any]:
    """
    Decodifica y verifica un JWT.

    Retorna el payload decodificado si es válido, o lanza `HTTPException(401)` si no.
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No se pudo validar el token de autenticación",
            headers={"WWW-Authenticate": "Bearer"},
        )
