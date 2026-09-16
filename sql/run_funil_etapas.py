import os
import duckdb

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DBT_PROJECT_DIR = os.path.join(SCRIPT_DIR, "..", "dbt", "rentcars_analytics")
DB_FILE = "dev.duckdb"
SQL_FILE = os.path.join(SCRIPT_DIR, "funil_etapas.sql")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "results")
OUTPUT_FILE = "funil_etapas.csv"
ROW_LIMIT = 1000


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with open(SQL_FILE, encoding="utf-8") as f:
        query = f.read()

    os.chdir(DBT_PROJECT_DIR)
    con = duckdb.connect(DB_FILE, read_only=True)

    df = con.execute(query).fetchdf()
    if len(df) > ROW_LIMIT:
        df = df.head(ROW_LIMIT)

    out_path = os.path.join(SCRIPT_DIR, "results", OUTPUT_FILE)
    df.to_csv(out_path, index=False)
    print(f"-> {len(df)} linha(s) salva(s) em {out_path}")

    con.close()


if __name__ == "__main__":
    main()
