#!/bin/bash
#SBATCH --job-name=metagenomics_pipeline
#SBATCH --output=metagenomics_%j.out
#SBATCH --partition=COMPUTE
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-cpu=6G
#SBATCH --time=72:00:00

# ================================
# Usage
# ================================
usage() { echo "Usage: $0 -w <workdir> -r <reads_dir> -f <fasta_dir> -o <output_dir>"; exit 1; }

while getopts "w:r:f:o:" opt; do
  case $opt in
    w) WORKDIR="$OPTARG" ;;
    r) READS_DIR="$OPTARG" ;;
    f) FASTA_DIR="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "$WORKDIR" || -z "$READS_DIR" || -z "$FASTA_DIR" || -z "$OUTPUT_DIR" ]] && usage

# ================================
# 1. Activate conda environment
# ================================
source ~/anaconda3/etc/profile.d/conda.sh
conda activate metawrap

THREADS=60
MEMORY=180
REFMEM=250

mkdir -p "$OUTPUT_DIR"

# ================================
# 2. Binning & Refinement (MetaWRAP)
# ================================
for FILE in "$FASTA_DIR"/*_contigs.fa "$FASTA_DIR"/*_contigs.fasta; do
  BASENAME=$(basename "$FILE" | sed 's/_contigs\.fasta\|_contigs\.fa//')
  READS="$READS_DIR/$BASENAME"/*.fastq

  BINNING_DIR="$OUTPUT_DIR/${BASENAME}_binning"
  REFINEMENT_DIR="$OUTPUT_DIR/${BASENAME}_refinement"
  mkdir -p "$BINNING_DIR" "$REFINEMENT_DIR"

  echo ">> Binning $BASENAME"
  metawrap binning --metabat2 --maxbin2 --concoct \
    -o "$BINNING_DIR" -a "$FILE" -m $MEMORY -t $THREADS $READS

  echo ">> Refinement $BASENAME"
  metawrap bin_refinement -o "$REFINEMENT_DIR" -t $THREADS \
    -A "$BINNING_DIR/metabat2_bins" \
    -B "$BINNING_DIR/maxbin2_bins" \
    -C "$BINNING_DIR/concoct_bins" \
    -c 70 -x 10
done

echo "✅ Binning & Refinement completed."

# ================================
# 3. Taxonomic classification of MAGs (GTDB-Tk)
# ================================
conda activate gtdbtk

GENOMES_DIR="$OUTPUT_DIR/dereplicated_genomes"
GTDB_OUT="$OUTPUT_DIR/gtdb_output"

gtdbtk classify_wf \
  --genome_dir "$GENOMES_DIR" \
  --out_dir "$GTDB_OUT" \
  --cpus $THREADS \
  --extension fa \
  --skip_ani_screen

echo "✅ GTDB-Tk classification completed."

# ================================
# 4. 16S sequence preprocessing (QIIME2)
# ================================
conda activate qiime2

# Remove BGI format prefix
for file in *.fq.gz; do
  mv "$file" "${file/RemovePrimer_Final./}"
done

# Create manifest for QIIME2
echo -e "sample-id\tforward-absolute-filepath\treverse-absolute-filepath" > manifest.txt

for forward in *_1.fastq.gz; do
  reverse="${forward/_1.fastq.gz/_2.fastq.gz}"
  sample_id="${forward%%_1.fastq.gz}"
  abs_forward="$(pwd)/$forward"
  abs_reverse="$(pwd)/$reverse"
  echo -e "$sample_id\t$abs_forward\t$abs_reverse" >> manifest.txt
done

# Import paired-end data
qiime tools import \
  --type 'SampleData[PairedEndSequencesWithQuality]' \
  --input-path manifest.txt \
  --output-path demux.qza \
  --input-format PairedEndFastqManifestPhred33V2

qiime demux summarize \
  --i-data demux.qza \
  --o-visualization demux.qzv

# ================================
# 5. Denoising with DADA2
# ================================
qiime dada2 denoise-paired \
  --i-demultiplexed-seqs demux.qza \
  --p-trunc-len-f 0 \
  --p-trunc-len-r 0 \
  --p-trim-left-r 20 \
  --p-trim-left-f 20 \
  --p-max-ee-f 5.0 \
  --p-max-ee-r 5.0 \
  --o-table table.qza \
  --o-representative-sequences rep-seqs.qza \
  --o-denoising-stats denoising-stats.qza

qiime metadata tabulate \
  --m-input-file denoising-stats.qza \
  --o-visualization stats-dada2.qzv

# ================================
# 6. Clustering, taxonomy & export
# ================================
qiime vsearch cluster-features-de-novo \
  --i-table table.qza \
  --i-sequences rep-seqs.qza \
  --p-perc-identity 0.99 \
  --o-clustered-table table-dn-99.qza \
  --o-clustered-sequences rep-seqs-dn-99.qza

qiime feature-table summarize \
  --i-table table.qza \
  --o-visualization table.qzv \
  --m-sample-metadata-file metadata.txt

qiime feature-table tabulate-seqs \
  --i-data rep-seqs.qza \
  --o-visualization rep-seqs.qzv

qiime feature-classifier classify-sklearn \
  --i-classifier ../silva138_AB_V3-V4_classifier.qza \
  --i-reads rep-seqs.qza \
  --o-classification taxonomy.qza

qiime metadata tabulate \
  --m-input-file taxonomy.qza \
  --o-visualization taxonomy.qzv

qiime tools export \
  --input-path table.qza \
  --output-path exported-feature-table

echo "✅ QIIME2 pipeline completed."
