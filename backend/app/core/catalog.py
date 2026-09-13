"""Canonical catalog-name comparison shared by validation and persistence."""
import unicodedata


def normalize_catalog_name(name: str) -> str:
    return unicodedata.normalize("NFKC", name).strip().casefold()
