#!/bin/bash -e

if [ $# -ne 6 ]; then
    echo "usage v1: lrna_align_tophat_pe.sh <tophat_index.tgz> <read1.fq.gz> <read2.fq.gz> <library_id> <ncpus> <bam_root>"
    echo "Align paired-end reads with TopHat/bowtie2.  Is independent of DX and encodeD."
    exit -1; 
fi
tophat_index_tgz=$1  # TopHat Index archive.
read1_fq_gz=$2       # gzipped fastq of of paired-end read1.
read2_fq_gz=$3       # gzipped fastq of of paired-end read2.
library_id=$4        # Library identifier which will be added to bam header.
ncpus=$5              # Number of cpus available.
bam_root="$6_tophat" # root name for output bam (e.g. "out_bam" will create "out_bam_tophat.bam") 

echo "-- Alignments file will be: '${bam_root}.bam'"

echo "-- Extracting TopHat index archive..."
tar zxvf $tophat_index_tgz
# unzips into "out/"

gff=`ls out/*.gff`
anno_prefix=${gff%.gff}
bamComments=`ls out/*_bamCommentLines.txt`
geno_prefix=${bamComments%_bamCommentLines.txt}
echo "-- Value of geno_prefix: '$geno_prefix'"
echo "-- Value of anno_prefix: '$anno_prefix'"

echo "-- Map reads..."
set -x
tophat -p $ncpus -z0 -a 8 -m 0 --min-intron-length 20 --max-intron-length 1000000 \
    --read-edit-dist 4 --read-mismatches 4 -g 20  --no-discordant --no-mixed \
    --library-type fr-firststrand --transcriptome-index $anno_prefix \
    $geno_prefix $read1_fq_gz $read2_fq_gz
set +x
ls -l tophat_out/accepted_hits.bam
ls -l tophat_out/unmapped.bam

echo "-- Set up headers..."
set -x
HD="@HD\tVN:1.4\tSO:coordinate" 
stCommand="perl tophat_bam_xsA_tag_fix.pl tophat_out/accepted_hits.bam | samtools view -bS - | samtools sort - mapped_fixed; samtools merge -h newHeader.sam merged.bam mapped_fixed.bam out/unmapped.bam"
newPG="@PG\tID:Samtools\tPN:Samtools\tCL:"$stCommand"\tPP:Tophat\tVN:VN:0.1.17 (r973:277)"
libraryComment="@CO\tLIBID:${library_id}"

samtools view -H tophat_out/accepted_hits.bam | \
gawk -v HD="$HD" -v newPG="$newPG" -v library="$libraryComment" \
    '{     if ($0 ~ /^@PG/) {PG=$0} 
      else if ($0 ~ /^@HD/) {print HD; }
      else if($0 ~ /^@SQ/) {print $0};
     }; END{print newPG"\n"PG"\n"library;}' > newHeader.sam

# Add reference genome and transcriptome used
cat ${geno_prefix}_bamCommentLines.txt >> newHeader.sam
set +x

echo "-- Fix unmapped bam and sort before merge..."
# Note single threaded input to samtools sort means single threaded sort
set -x
perl /usr/bin/tophat_bam_xsA_tag_fix.pl tophat_out/accepted_hits.bam | \
            samtools view -bS - | samtools sort - mapped_fixed
set +x
ls -l mapped_fixed.bam

echo "-- Merge aligned and unaligned into single bam, using the patched up header..."
set -x
samtools merge -@ $ncpus -h newHeader.sam merged.bam mapped_fixed.bam tophat_out/unmapped.bam
mv merged.bam ${bam_root}.bam
set +x
ls -l ${bam_root}.bam

echo "-- Collect bam flagstats..."
set -x
samtools flagstat ${bam_root}.bam > ${bam_root}_flagstat.txt
set +x

echo "-- The results..."
ls -l ${bam_root}*

