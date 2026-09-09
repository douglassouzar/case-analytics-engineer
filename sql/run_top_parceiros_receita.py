"""
Executa a query de receita_parceiros.sql (Q2) contra o DuckDB local
materializado pelo dbt (dbt/rentcars_analytics/dev.duckdb) e exporta o
resultado em CSV.

Uso (com o venv do projeto ativado, de qualquer pasta):
    python run_receita_parceiros.py
"""

import os
import duckdb

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DBT_PROJECT_DIR = os.path.join(SCRIPT_DIR, "..", "dbt", "rentcars_analytics")
DB_FILE = "dev.duckdb"
SQL_FILE = os.path.join(SCRIPT_DIR, "top_parceiros_receita.sql")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "results")
OUTPUT_FILE = "top_parceiros_receita.csv"
ROW_LIMIT = 1000


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with open(SQL_FILE, encoding="utf-8") as f:
        query = f.read()

    # importante: muda o cwd para a pasta do projeto dbt ANTES de conectar.
    # Os sources (models/staging/sources.yml) apontam para os CSVs com
    # caminho relativo (data/raw_*.csv), e o DuckDB resolve esse caminho em
    # relação ao cwd do processo Python, não em relação à localização do
    # arquivo .duckdb — por isso o script precisa "entrar" na pasta do
    # projeto dbt antes de rodar a query.
    os.chdir(DBT_PROJECT_DIR)
    con = duckdb.connect(DB_FILE, read_only=True)

    print("Rodando receita_parceiros...")
    df = con.execute(query).fetchdf()

    if len(df) > ROW_LIMIT:
        df = df.head(ROW_LIMIT)

    out_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    df.to_csv(out_path, index=False)
    print(f"  -> {len(df)} linha(s) salva(s) em {out_path}")

    con.close()


if __name__ == "__main__":
    main()
