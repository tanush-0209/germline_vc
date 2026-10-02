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


# Week 2 — Slurm

## Failure 1: --time=00:02:00 timeout (deliberate)
- Trigger: sbatch -p courses -A binf6610.202710 --array=3 --time=00:02:00 01_persample.sbatch
- sacct:
    10763191_3      TIMEOUT   00:02:09      0:0
    10763191_3.+  CANCELLED   00:02:10     0:15
    10763191_3.+  COMPLETED   00:02:10      0:0
- Where it stopped: stages 0-4 (validate, qc_raw, trim, align, postprocess) all
  completed successfully and logged OK. It was killed mid-way through stage 5
  (quantify / HaplotypeCaller), the single longest-running stage, with the log
  ending on "slurmstepd: error: *** JOB ... CANCELLED ... DUE TO TIME LIMIT ***".
- What was left on disk: a truncated NA12892.g.vcf.gz (4,032,356 bytes,
  timestamped at the kill), sitting next to a stale .tbi index file from an
  earlier, successful full run six hours prior. The presence of a .tbi index
  is therefore not reliable evidence that its matching GVCF is complete - it
  can belong to a previous, different run of the same file.

## Failure 2: forced task failure under afterok (deliberate)
- Trigger: submitted --array=1,9 against the 8-row samplesheet (task 9 is
  out-of-range and hits the stage_validate guard), with the cohort job
  attached via afterok:
    ARRAY_JOB=$(sbatch -p courses -A binf6610.202710 --array=1,9 --parsable 01_persample.sbatch)
    sbatch -p courses -A binf6610.202710 --dependency=afterok:${ARRAY_JOB} --kill-on-invalid-dep=yes --parsable 02_cohort.sbatch
- sacct (array):
    10763322_1      RUNNING      0:0   00:02:19
    10763322_9       FAILED     64:0   00:00:01
- sacct (cohort):
    10763324      CANCELLED      0:0             Dependency
- What happened: task 1 (a real sample) ran normally; task 9 failed in 1
  second against its out-of-range guard, exit code 64. Once task 1 finished,
  the array was no longer all-success, and Explorer automatically cancelled
  the cohort job (reason: Dependency) rather than letting it start on an
  incomplete set of GVCFs. This is Explorer's kill_invalid_depend setting;
  --kill-on-invalid-dep=yes makes this happen on any cluster, not just ones
  that default to it.

## Failure 3: out-of-range array index (deliberate)
- Trigger: submitted --array=9 against the 8-row samplesheet, both with and
  without the stage_validate guard in 01_persample.sbatch commented out.
- With the guard: task 9 failed in 1 second, exit code 64, logging
  "task 9: no such row".
- Without the guard: task 9 still failed, in 5 seconds, exit code 1 - but
  for a different reason than expected. awk returned an empty SAMPLE, and
  01_persample.sbatch passed that empty value as run_sample.sh's third
  argument. run_sample.sh's own argument parsing uses bash's ${3:?message}
  syntax, which refuses an unset or empty value on its own:
    /home/.../run_sample.sh: line 9: 3: usage: run_sample.sh SAMPLESHEET OUTDIR SAMPLE_ID [LAST_STAGE]
- What this means: the explicit guard in 01_persample.sbatch turned out to
  be redundant with run_sample.sh's own argument check - removing it did
  not cause the task to silently process every sample (what I expected
  going in), because a second, independent safety net caught the same
  problem first. The guard is still worth keeping explicitly, since it
  fails faster (1s vs 5s) and with a clearer, purpose-written message
  naming the actual array task number - but this run showed the failure
  mode is not as silent as it could have been, because of a second
  bash-level check elsewhere in the pipeline.

## Failure 4: scancel mid-write, then resubmit (deliberate)
- Trigger: submitted --array=6 (NA10851), cancelled it mid-stage-3 (align),
  then resubmitted the same task.
- First run: stopped after "stage 3 : align" with no "OK" line logged;
  slurmstepd confirmed CANCELLED right after. align/NA10851.bwa.log got a
  fresh timestamp, but NA10851.sorted.bam kept its old timestamp - the sort
  hadn't finished writing before the cancel.
- Rerun (10763533): COMPLETED, exit 0:0, 00:06:14. NA10851.g.vcf.gz and its
  .tbi both carry fresh, matching timestamps.
- What this shows: the rerun trusted nothing from the killed run - every
  stage unconditionally overwrites its output, so stale files were just
  replaced with no corruption or special handling. This only works because
  the pipeline has no resume/skip-if-exists logic; adding one later without
  care could mistake a stale partial file for finished output.
