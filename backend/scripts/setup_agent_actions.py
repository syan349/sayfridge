"""Add/check the business receipt table in an existing database; never startup DDL."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import create_engine, inspect
from app.core.config import get_settings
from app.db.models import AgentInventoryAction


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--initialize", action="store_true")
    args = parser.parse_args()
    engine = create_engine(get_settings().database_url_direct.get_secret_value(), hide_parameters=True)
    try:
        with engine.connect() as conn:
            schema = inspect(conn).default_schema_name
            print(f"Business table: {schema}.agent_inventory_action (connection details hidden)")
            exists = inspect(conn).has_table("agent_inventory_action")
            print(f"Table exists: {exists}")
            if args.initialize and not exists:
                if input("Type INITIALIZE to add the receipt table: ").strip() != "INITIALIZE":
                    return
                AgentInventoryAction.__table__.create(conn, checkfirst=True)
                conn.commit()
                exists = True
            if exists:
                columns = inspect(conn).get_columns("agent_inventory_action")
                actual = {c["name"] for c in columns}
                expected = set(AgentInventoryAction.__table__.columns.keys())
                if actual != expected:
                    raise RuntimeError("Receipt columns differ from the model")
                for c in columns:
                    model_column = AgentInventoryAction.__table__.columns[c["name"]]
                    if c["nullable"] != model_column.nullable or str(c["type"].compile(dialect=engine.dialect)) != str(model_column.type.compile(dialect=engine.dialect)):
                        raise RuntimeError("Receipt column types/nullability differ from model")
                if inspect(conn).get_pk_constraint("agent_inventory_action")["constrained_columns"] != ["id"]:
                    raise RuntimeError("Receipt primary key differs from model")
                print("Column structure and primary key: passed")
            elif args.check:
                raise RuntimeError("Receipt table must be initialized before enabling Agent writes")
    except Exception as exc:
        print(f"Check failed ({type(exc).__name__}); no automatic cleanup performed.", file=sys.stderr)
        raise SystemExit(1) from None
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
