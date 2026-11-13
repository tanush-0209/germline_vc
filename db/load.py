#!/usr/bin/env python3
"""Load variant-call runs and sample metadata into a SQLite database.

    python3 db/load.py <database> <metadata.tsv> <run folder> [<run folder> ...]
"""
import csv
import json
import os
import sys


def read_tsv(path):
    """A TSV file's rows as dicts, keyed by its header line."""
    with open(path, newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def read_metadata(path):
    """The sample metadata file's rows as dicts. Lines starting with # are notes, skipped."""
    with open(path, newline="") as f:
        lines = [line for line in f if not line.startswith("#")]
    return list(csv.DictReader(lines, delimiter="\t"))


def zero_to_none(value):
    """father/mother: 0 means no parent recorded."""
    return None if value in ("0", "") else value


def bool_to_int(value):
    """is_synthetic_phenotype: true/false, as the metadata writes it, to 1/0."""
    return 1 if value.strip().lower() in ("true", "1") else 0


def load_metadata(con, path):
    """Every row of the metadata file into samples. Already-there rows are left alone."""
    rows = read_metadata(path)
    for row in rows:
        con.execute(
            "INSERT INTO samples (sample_id, sex, population, family, father, mother,"
            " phenotype, is_synthetic_phenotype) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            " ON CONFLICT (sample_id) DO NOTHING",
            (
                row["sample_id"],
                row["sex"] or None,
                row["population"] or None,
                row["family"] or None,
                zero_to_none(row["father"]),
                zero_to_none(row["mother"]),
                row["phenotype"] or None,
                bool_to_int(row["is_synthetic_phenotype"]),
            ),
        )
    return f"metadata: {len(rows)} samples"


def load_run(con, folder):
    """Everything one run published. Returns a line saying what happened."""
    with open(os.path.join(folder, "manifest.json")) as f:
        manifest = json.load(f)
    pipeline = manifest["pipeline"]
    run_id = pipeline["run_id"]

    # Loading twice changes nothing: a run that is already here is left as it is.
    if con.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,)).fetchone():
        return f"{run_id}: already in the database, skipped"

    # pipelines: runs share a pipeline version, so it is added only if new.
    version = (pipeline["name"], pipeline["version"], pipeline["implementation"])
    con.execute(
        "INSERT INTO pipelines (name, version, implementation) VALUES (?, ?, ?)"
        " ON CONFLICT (name, version, implementation) DO NOTHING",
        version,
    )
    pipeline_id = con.execute(
        "SELECT pipeline_id FROM pipelines WHERE name = ? AND version = ? AND implementation = ?",
        version,
    ).fetchone()[0]

    # runs: a plain INSERT, no ON CONFLICT — an error here undoes the whole run.
    params, platform = manifest["params"], manifest["platform"]
    con.execute(
        "INSERT INTO runs (run_id, pipeline_id, started_at, finished_at, exit_status,"
        " platform, executor, samplesheet, reference, region, folder)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            run_id,
            pipeline_id,
            pipeline["started_at"],
            pipeline["finished_at"],
            pipeline["exit_status"],
            platform["kind"],
            platform["executor"],
            params["samplesheet"],
            params["ref"],
            params.get("region"),
            os.path.abspath(folder),
        ),
    )

    # samples: a blank row for any sample the metadata does not list (the smoke samples).
    sample_ids = [s["sample_id"] for s in manifest["samples"]]
    for sample_id in sample_ids:
        con.execute(
            "INSERT INTO samples (sample_id) VALUES (?) ON CONFLICT (sample_id) DO NOTHING",
            (sample_id,),
        )

    # run_samples: the same sample twice in one run breaks its key, and undoes the whole run.
    for s in manifest["samples"]:
        con.execute(
            "INSERT INTO run_samples (run_id, sample_id, condition, library_type)"
            " VALUES (?, ?, ?, ?)",
            (run_id, s["sample_id"], s["condition"], s["library_type"]),
        )

    # variants: one row for each line of variants.tsv.
    variant_rows = read_tsv(os.path.join(folder, "variants.tsv"))
    variants = [
        (run_id, r["chrom"], int(r["pos"]), r["ref"], r["alt"], float(r["qual"]), r["filter"])
        for r in variant_rows
    ]
    con.executemany(
        "INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)",
        variants,
    )

    # outputs: one row for each file the manifest names, with its checksum's 64 characters.
    for o in manifest["outputs"]:
        sha256 = o["checksum"].split(":", 1)[1]
        con.execute(
            "INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)",
            (run_id, o["path"], sha256),
        )

    return (
        f"{run_id}: loaded {len(sample_ids)} samples, {len(variants)} variants,"
        f" {len(manifest['outputs'])} files"
    )


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: python3 db/load.py <database> <metadata.tsv> <run folder> [...]")
    database, metadata, folders = sys.argv[1], sys.argv[2], sys.argv[3:]

    con = sqlite3.connect(database)
    con.execute("PRAGMA foreign_keys = ON")  # on this connection, every time

    with con:
        print(load_metadata(con, metadata))

    for folder in folders:
        with con:  # one transaction for each run: commit at its end, or undo the whole run
            print(load_run(con, folder))

    con.close()


if __name__ == "__main__":
    import sqlite3
    main()
