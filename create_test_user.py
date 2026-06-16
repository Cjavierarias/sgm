"""
Crea usuarios de prueba con distintos roles para testear el sistema.

Uso: python create_test_user.py
(Desde la raíz del proyecto con el env sgm activado)
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "backend"))

from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), "backend", ".env"))

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import select
from app.models.base import Base, Company, User, UserRole, RoleName
from app.services.auth import get_password_hash
import os

DATABASE_URL = os.getenv("DATABASE_URL")


async def create_users():
    engine = create_async_engine(DATABASE_URL, echo=False)
    SessionLocal = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with SessionLocal() as db:
        # Verificar si ya existe la empresa demo
        res = await db.execute(select(Company).where(Company.name == "Empresa Demo SGM"))
        company = res.scalars().first()
        if not company:
            company = Company(name="Empresa Demo SGM")
            db.add(company)
            await db.flush()
            print(f"✓ Empresa creada: {company.name} (id={company.id})")
        else:
            print(f"→ Empresa ya existe: {company.name} (id={company.id})")

        users_to_create = [
            {
                "email": "admin@example.com",
                "password": "password123",
                "full_name": "Admin Principal",
                "position": "Administrador",
                "roles": [RoleName.admin],
            },
            {
                "email": "jefe@example.com",
                "password": "password123",
                "full_name": "Juan Jefe",
                "position": "Jefe de Mantenimiento",
                "roles": [RoleName.maintenance_manager],
            },
            {
                "email": "tecnico@example.com",
                "password": "password123",
                "full_name": "Carlos Técnico",
                "position": "Mecánico",
                "roles": [RoleName.technician],
            },
            {
                "email": "deposito@example.com",
                "password": "password123",
                "full_name": "María Depósito",
                "position": "Encargada de Almacén",
                "roles": [RoleName.warehouse],
            },
            {
                "email": "compras@example.com",
                "password": "password123",
                "full_name": "Pedro Compras",
                "position": "Responsable de Compras",
                "roles": [RoleName.purchasing],
            },
            # Usuario con múltiples roles
            {
                "email": "test@example.com",
                "password": "password123",
                "full_name": "Usuario Test",
                "position": "Multi-rol",
                "roles": [RoleName.admin, RoleName.maintenance_manager],
            },
        ]

        for u_data in users_to_create:
            res = await db.execute(select(User).where(User.email == u_data["email"]))
            existing = res.scalars().first()
            if existing:
                print(f"→ Ya existe: {u_data['email']}")
                continue

            user = User(
                email=u_data["email"],
                full_name=u_data["full_name"],
                position=u_data["position"],
                hashed_password=get_password_hash(u_data["password"]),
                company_id=company.id,
            )
            db.add(user)
            await db.flush()

            for role in u_data["roles"]:
                db.add(UserRole(user_id=user.id, role=role))

            print(f"✓ Creado: {u_data['email']} — roles: {[r.value for r in u_data['roles']]}")

        await db.commit()

    await engine.dispose()
    print("\n✅ Listo. Usuarios disponibles:")
    print("   admin@example.com     / password123  → Admin")
    print("   jefe@example.com      / password123  → Jefe Mantenimiento")
    print("   tecnico@example.com   / password123  → Técnico")
    print("   deposito@example.com  / password123  → Depósito")
    print("   compras@example.com   / password123  → Compras")
    print("   test@example.com      / password123  → Admin + Jefe")


if __name__ == "__main__":
    asyncio.run(create_users())
