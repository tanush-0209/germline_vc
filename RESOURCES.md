# Resource measurement — slurm/01_persample.sbatch

## Core-count comparison
Same sample (NA12878), same stage set (validate → quantify), run at four
different `--cpus-per-task` values to find the knee in the curve.

| Cores | Elapsed  | MaxRSS   | Core-minutes spent |
|-------|----------|----------|---------------------|
| 4     | 9m 07s   | 6.96 GB  | 36.5                |
| 8     | 7m 52s   | 8.01 GB  | 63.0                |
| 16    | 6m 30s   | 7.09 GB  | 104.0               |
| 28    | 6m 12s   | 12.77 GB | 173.6               |

**Decision: `--cpus-per-task=16`.**

Going from 16 to 28 cores bought only 18 seconds (6m30s → 6m12s), while
memory usage nearly doubled (7.09 GB → 12.77 GB) and core-minutes spent
jumped from 104 to 174 for almost no benefit. 16 cores captures nearly
all of the achievable speedup (within 3% of the 28-core time) without
that memory cost, and without reserving far more of a shared node than
the work can actually use.

## Memory
MaxRSS across all four runs ranged 6.96–12.77 GB, with the 28-core run
as an outlier — more threads meant more parallel buffering, not more
useful work. At the chosen 16-core setting, peak usage was 7.09 GB.

**Decision: `--mem=10G`** — comfortable headroom above the measured
7.09 GB peak, without requesting far more than is used (the original
guess of 16G would have been roughly 2.25x the actual peak).

## Time limit
All single-sample runs, across every core count tested, finished in
under 10 minutes. `--time=00:30:00` leaves generous headroom for
slower nodes or larger per-sample variance without being needlessly
long.

## Cohort job (stages 6-9)
Not yet separately measured — the cohort job has not completed
successfully yet, since it was tested against a partial (2-sample)
array and failed on a missing GVCF for an untested sample, not a
resource issue. Its resource settings (`--cpus-per-task=2 --mem=4G
--time=00:30:00`) are provisional and will be re-measured against the
full 8-sample run.
