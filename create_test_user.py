#!/usr/bin/env python3
"""
Script para crear un usuario de prueba en la base de datos.
Uso: python3 create_test_user.py
"""
import asyncio
import os
import sys
from pathlib import Path

# Añadir backend al path
sys.path.insert(0, str(Path(__file__).parent / "backend"))

from app.database import engine, get_db
from app.models.base import Base, User, Company
from app.services.auth import get_password_hash
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

async def main():
    """Crea tablas y un usuario de prueba."""
    
    # Crear tablas
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        print("✓ Tablas creadas o ya existen")
    
    # Crear empresa de prueba
    async with AsyncSession(engine) as session:
        # Verificar si la empresa existe
        result = await session.execute(select(Company).where(Company.name == "Test Company"))
        company = result.scalars().first()
        
        if not company:
            company = Company(name="Test Company")
            session.add(company)
            await session.flush()
            print(f"✓ Empresa creada: {company.name} (ID: {company.id})")
        else:
            print(f"✓ Empresa existe: {company.name} (ID: {company.id})")
        
        # Crear usuario de prueba
        test_email = "test@example.com"
        test_password = "password123"
        
        result = await session.execute(select(User).where(User.email == test_email))
        user = result.scalars().first()
        
        if not user:
            hashed_pw = get_password_hash(test_password)
            user = User(
                email=test_email,
                hashed_password=hashed_pw,
                company_id=company.id,
                role="technician"
            )
            session.add(user)
            await session.flush()
            print(f"✓ Usuario creado: {test_email}")
            print(f"  Contraseña: {test_password}")
            print(f"  ID: {user.id}")
        else:
            print(f"✓ Usuario existe: {test_email}")
        
        await session.commit()
        print("\n✓ Todo completado. Puedes iniciar sesión con:")
        print(f"  Email: {test_email}")
        print(f"  Contraseña: {test_password}")

if __name__ == "__main__":
    asyncio.run(main())
