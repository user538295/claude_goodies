#!/usr/bin/env python3
"""Regenerate report.xlsx from the accumulated result TSVs. Idempotent — run after each file.

Raw rows land in data_hits / data_adj / data_llm sheets; every aggregate cell is an
Excel formula (COUNTIFS/SUM/IF) referencing them, so the workbook is auditable and
recomputes if the data sheets are edited.
"""
import csv
import os

from openpyxl import Workbook
from openpyxl.formatting.rule import ColorScaleRule, FormulaRule
from openpyxl.styles import Font, PatternFill

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")
MATCH_TOLERANCE_LINES = 3
PROJECTS = ["archon-search", "moonset", "financialwell", "dddd", "udemy-top-down-shooter"]


def read_tsv(name):
    path = os.path.join(RESULTS, name)
    if not os.path.exists(path):
        return []
    with open(path, newline="") as f:
        return [r for r in csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE)
                if r and not r[0].startswith("#")]


def main():
    catalog = {}  # id -> (severity, title)
    with open(os.path.join(RESULTS, "catalog.txt")) as f:
        for line in f:
            cid, sev, title = [p.strip() for p in line.strip().split("·", 2)]
            catalog[cid] = (sev, title)

    files = []
    with open(os.path.join(HERE, "files.tsv")) as f:
        for r in csv.reader(f, delimiter="\t"):
            if r and not r[0].startswith("#"):
                files.append(r)

    hits = read_tsv("hits.tsv")            # project, file, check, line, excerpt
    adjs = read_tsv("adjudications.tsv")   # project, file, check, line, verdict, reason
    llm = read_tsv("llmonly.tsv")          # project, file, check, line, note

    hit_lines = {}
    file_level_hits = set()  # (check, file) hits that measure the whole file — match by file, not line
    for _p, fp, c, ln, ex, *_ in hits:
        hit_lines.setdefault((c, fp), set()).add(int(ln))
        if ex.startswith("file-level:"):
            file_level_hits.add((c, fp))

    wb = Workbook()
    grey = PatternFill("solid", start_color="DDDDDD")
    bold = Font(bold=True)

    def data_sheet(name, header, rows):
        ws = wb.create_sheet(name)
        ws.append(header)
        for cell in ws[1]:
            cell.font = bold
        for r in rows:
            ws.append(r)
        ws.freeze_panes = "A2"

    def check_sheet(ws, projects):
        header = (["check", "severity", "title"] + [f"hits:{p}" for p in projects] +
                  ["hits total", "adjudicated", "TP", "FP", "precision %",
                   "LLM-only found", "overlap w/ script", "script misses",
                   "script coverage %", "est. true hits"])
        ws.append(header)
        for cell in ws[1]:
            cell.font = bold
        n = len(projects)
        col = lambda i: chr(ord("A") + i)  # noqa: E731 — 16 cols max, stays in A..Z
        first_hit, total_c = 3, 3 + n
        adj_c, tp_c, fp_c, prec_c = total_c + 1, total_c + 2, total_c + 3, total_c + 4
        llm_c, ovl_c, miss_c = total_c + 5, total_c + 6, total_c + 7
        last_c = total_c + 9  # + script coverage %, est. true hits
        for i, cid in enumerate(sorted(catalog)):
            row_i = i + 2
            sev, title = catalog[cid]
            row = [cid, sev, title]
            for p in projects:
                row.append(f'=COUNTIFS(data_hits!$A:$A,"{p}",data_hits!$C:$C,$A{row_i})')
            row.append(f"=SUM({col(first_hit)}{row_i}:{col(total_c - 1)}{row_i})")
            row.append(f"={col(tp_c)}{row_i}+{col(fp_c)}{row_i}")
            if n > 1:
                verdict = 'data_adj!$E:$E'
                row.append(f'=COUNTIFS(data_adj!$C:$C,$A{row_i},{verdict},"TP")')
                row.append(f'=COUNTIFS(data_adj!$C:$C,$A{row_i},{verdict},"FP")')
            else:
                p = projects[0]
                row.append(f'=COUNTIFS(data_adj!$A:$A,"{p}",data_adj!$C:$C,$A{row_i},data_adj!$E:$E,"TP")')
                row.append(f'=COUNTIFS(data_adj!$A:$A,"{p}",data_adj!$C:$C,$A{row_i},data_adj!$E:$E,"FP")')
            row.append(f'=IF({col(adj_c)}{row_i}=0,"",ROUND(100*{col(tp_c)}{row_i}/{col(adj_c)}{row_i},1))')
            if n > 1:
                row.append(f'=COUNTIFS(data_llm!$C:$C,$A{row_i})')
                row.append(f'=COUNTIFS(data_llm!$C:$C,$A{row_i},data_llm!$F:$F,TRUE)')
            else:
                p = projects[0]
                row.append(f'=COUNTIFS(data_llm!$A:$A,"{p}",data_llm!$C:$C,$A{row_i})')
                row.append(f'=COUNTIFS(data_llm!$A:$A,"{p}",data_llm!$C:$C,$A{row_i},data_llm!$F:$F,TRUE)')
            row.append(f"={col(llm_c)}{row_i}-{col(ovl_c)}{row_i}")
            row.append(f'=IF({col(llm_c)}{row_i}=0,"",ROUND(100*{col(ovl_c)}{row_i}/{col(llm_c)}{row_i},1))')
            row.append(f'=IF({col(adj_c)}{row_i}=0,"",ROUND({col(total_c)}{row_i}*{col(tp_c)}{row_i}/{col(adj_c)}{row_i},0))')
            ws.append(row)
        last = ws.max_row
        rng = f"A2:{col(last_c)}{last}"
        ws.conditional_formatting.add(
            rng, FormulaRule(formula=[f"${col(total_c)}2=0"], fill=grey))
        pc = col(prec_c)
        ws.conditional_formatting.add(
            f"{pc}2:{pc}{last}",
            ColorScaleRule(start_type="num", start_value=0, start_color="F8696B",
                           mid_type="num", mid_value=50, mid_color="FFEB84",
                           end_type="num", end_value=100, end_color="63BE7B"))
        ws.freeze_panes = "A2"

    check_sheet(wb.active, PROJECTS)
    wb.active.title = "Summary"
    for p in PROJECTS:
        check_sheet(wb.create_sheet(p[:31]), [p])

    ws = wb.create_sheet("Files")
    ws.append(["project", "path", "lines", "role", "stratum", "script hits", "processed"])
    for cell in ws[1]:
        cell.font = bold
    done = {r[0] for r in read_tsv("progress.tsv")}
    for i, (proj, path, lines, role, stratum) in enumerate(files):
        ws.append([proj, path, int(lines), role, stratum,
                   f'=COUNTIFS(data_hits!$B:$B,$B{i + 2})',
                   "yes" if path in done else ""])
    ws.freeze_panes = "A2"

    ws = wb.create_sheet("Method")
    for row in [
        ["model", "sonnet (adjudication + LLM-only agents)"],
        ["execution", "serial per file: collect.sh -> adjudicate -> LLM-only -> rebuild xlsx"],
        ["adjudication sample", "files 1-12: first 15 hits per check per file; files 13-46: all hits"],
        ["script coverage %", "overlap / LLM-only found (recall proxy, formula)"],
        ["est. true hits", "hits total x precision (script haul corrected for FPs, formula)"],
        ["LLM-only repeats", "1 (token budget; variance not measured)"],
        ["LLM-only input", "catalog of 60 scriptable checks (id/severity/title), hits withheld"],
        ["match tolerance", f"same check + file, ±{MATCH_TOLERANCE_LINES} lines (data_llm.matched, computed at build time)"],
        ["HIT_CAP", "200 (as shipped, per-file runs, no cap warnings observed unless noted)"],
        ["file selection", "files.tsv (frozen 2026-08-24)"],
        ["precision", "TP / adjudicated script hits (formula)"],
        ["script misses", "LLM-only found - overlap (formula)"],
        ["aggregates", "all counts are COUNTIFS/SUM formulas over data_hits/data_adj/data_llm"],
    ]:
        ws.append(row)

    data_sheet("data_hits", ["project", "file", "check", "line", "excerpt"],
               [[p, f, c, int(ln), ex] for p, f, c, ln, ex in (r[:5] for r in hits)])
    data_sheet("data_adj", ["project", "file", "check", "line", "verdict", "reason"],
               [[p, f, c, int(ln), v, rs] for p, f, c, ln, v, rs in (r[:6] for r in adjs)])
    llm_rows = []
    for p, fpath, c, ln, note in (r[:5] for r in llm):
        matched = ((c, fpath) in file_level_hits or
                   any(abs(int(ln) - h) <= MATCH_TOLERANCE_LINES
                       for h in hit_lines.get((c, fpath), ())))
        llm_rows.append([p, fpath, c, int(ln), note, matched])
    data_sheet("data_llm", ["project", "file", "check", "line", "note", "matched"], llm_rows)

    wb.save(os.path.join(HERE, "report.xlsx"))
    print("report.xlsx written:",
          f"{len(hits)} hits, {len(adjs)} adjudications, {len(llm)} llm-only findings")


if __name__ == "__main__":
    main()
