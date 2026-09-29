# Troubleshooting Log

## FastQC not installed
- **Symptom:** running `fastqc --version` returned `command not found`.
- **Evidence:** the error message itself confirmed FastQC wasn't on PATH at all, rather than being a broken or misconfigured install.
- **Cause:** FastQC had never been installed on this machine.
- **Fix:** installed it directly, then re-ran `fastqc --version` and confirmed it reported `FastQC v0.11.9`.

## write_manifest.sh: wrong path when copying into the repo
- **Symptom:** `cp` failed with `cannot stat '.../w01-demo-pipeline-bash/rnaseq-week1/lib/write_manifest.sh': No such file or directory` when trying to copy the manifest script into `germline_vc/lib/`.
- **Evidence:** ran `find "Week_1" -iname "write_manifest.sh"` to search the whole course folder for the file, since I wasn't sure exactly where the demo zip had extracted to.
- **Cause:** the demo pipeline zip had extracted directly to `Week_1/rnaseq-week1/`, with no `w01-demo-pipeline-bash` wrapper folder — I'd assumed the extracted folder name matched the zip's name, which was wrong.
- **Fix:** re-ran the `cp` command pointing at the correct path (`Week_1/rnaseq-week1/lib/write_manifest.sh`), confirmed with `ls` that it landed correctly in `germline_vc/lib/`.
