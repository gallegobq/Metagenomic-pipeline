# Metagenomics Pipeline

This repository contains a reproducible workflow for **metagenomic binning, dereplication, taxonomic classification (GTDB-Tk), and 16S amplicon analysis (QIIME2)**.  
It integrates tools such as MetaWRAP, dRep, GTDB-Tk, and QIIME2 into a single automated workflow.

---

## Requirements

- Linux system (HPC or local server)
- [Conda](https://docs.conda.io/projects/conda/en/latest/)
- [MetaWRAP](https://github.com/bxlab/metaWRAP)
- [dRep](https://github.com/MrOlm/drep)
- [GTDB-Tk](https://ecogenomics.github.io/GTDBTk/)
- [QIIME2](https://qiime2.org/)

---

## Usage

```bash
# Example SLURM submission
sbatch pipeline.sh -w <workdir> -r <reads_dir> -f <fasta_dir> -o <output_dir>

---

## Citation

If you use this pipeline, please cite:

> DOI: [10.5281/zenodo.17196561](https://doi.org/10.5281/zenodo.17196561)

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.17196561.svg)](https://doi.org/10.5281/zenodo.17196561)



