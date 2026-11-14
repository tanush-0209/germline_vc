#!/usr/bin/env python3
"""A results page for the variant-call runs in week-9's database.

    python3 dashboard/app.py <database> [<port>]
"""
import os
import sqlite3
import sys
from urllib.parse import parse_qs

import dash_ag_grid as dag
import pandas as pd
import plotly.express as px
from dash import Dash, Input, Output, callback, ctx, dcc, html
from dash.exceptions import PreventUpdate

DB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050

HERE = os.path.dirname(os.path.abspath(__file__))
Q1_SQL = os.path.join(HERE, "..", "db", "queries", "q1.sql")


def query(sql, params=()):
    """Run one SQL statement on a connection of its own, and return the rows."""
    con = sqlite3.connect(DB)
    rows = pd.read_sql_query(sql, con, params=params)
    con.close()
    return rows


def grid(component_id, df):
    """An AG Grid over a pandas table."""
    return dag.AgGrid(
        id=component_id,
        rowData=df.to_dict("records"),
        columnDefs=[{"field": c} for c in df.columns],
        columnSize="sizeToFit",
    )


def runs_page():
    with open(Q1_SQL) as f:
        runs = query(f.read())
    links = [
        html.Li(dcc.Link(r, href=f"/results?run={r}"))
        for r in runs["run_id"]
    ]
    return [
        html.H1("The runs in " + DB),
        html.Ul(links),
        grid("runs-table", runs),
    ]


def results_page(run_id):
    samples = query(
        """
        SELECT run_samples.sample_id AS sample_id,
               run_samples.condition AS condition,
               samples.phenotype AS phenotype,
               samples.is_synthetic_phenotype AS is_synthetic_phenotype
        FROM run_samples
        JOIN samples ON samples.sample_id = run_samples.sample_id
        WHERE run_samples.run_id = ?
        """,
        (run_id,),
    )
    sites = query(
        'SELECT chrom, pos, ref, alt, qual, "filter" FROM variants WHERE run_id = ?',
        (run_id,),
    )

    plot_filter = px.histogram(
        sites, x="filter",
        title="How many sites passed, and why did the others fail?",
    )
    plot_qual = px.histogram(
        sites, x="qual",
        title="How confident are the calls?",
    )
    plot_position = px.histogram(
        sites, x="pos",
        title="Where along the region are the sites?",
    )

    return [
        html.H1(f"Results of {run_id}"),
        grid("samples-table", samples),
        dcc.Graph(id="plot-filter", figure=plot_filter),
        dcc.Graph(id="plot-qual", figure=plot_qual),
        dcc.Graph(id="plot-position", figure=plot_position),
        grid("sites-table", sites),
    ]


app = Dash(__name__, suppress_callback_exceptions=True)
app.layout = [dcc.Location(id="url"), html.Div(id="page", children=[])]


@callback(
    Output("page", "children"),
    Input("url", "pathname"), Input("url", "search"),
)
def draw_page(pathname, search):
    if pathname == "/results":
        run_id = parse_qs(search.lstrip("?"))["run"][0]
        return results_page(run_id)
    return runs_page()


@callback(
    Output("sites-table", "rowData"),
    Input("plot-filter", "clickData"),
    Input("url", "search"),
)
def narrow_sites(click, search):
    parsed = parse_qs(search.lstrip("?")) if search else {}
    if "run" not in parsed:
        raise PreventUpdate
    run_id = parsed["run"][0]
    if click is None:
        sites = query(
            'SELECT chrom, pos, ref, alt, qual, "filter" FROM variants WHERE run_id = ?',
            (run_id,),
        )
    else:
        value = click["points"][0]["x"]
        sites = query(
            'SELECT chrom, pos, ref, alt, qual, "filter" FROM variants'
            ' WHERE run_id = ? AND "filter" = ?',
            (run_id, value),
        )
    return sites.to_dict("records")


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
