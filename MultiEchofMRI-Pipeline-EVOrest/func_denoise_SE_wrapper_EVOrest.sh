#!/bin/bash
# Denoise Functional Data (3rd of 3 wrappers in the ME pipeline); Single-Echo Version
# Charles Lynch, Hussain Bukhari, Holland Brown
# Updated 2023-09-15

# ---------------------- Important User-Defined Parameters ----------------------

StudyFolder=$1 # location of Subject folder
Subject=$2 # space delimited list of subject IDs
NTHREADS=$3 # set number of threads; larger values will reduce runtime (but also increase RAM usage)
StartSession=$4

RunICAAROMA=true # Motion correction and artifact identification with ICA-AROMA (run this for EVO participants)
RunMGTR=false # NOTE: PIs decided not to run MGTR script for EVO study (see Chuck's papers on gray-ordinates for more info)
Vol2FirstSurf=true # project denoised volumes onto a surface
SmoothVol2SecondSurf=true # additional 1.75 mm smoothing before projecting onto a second surface

# Set directories to scripts and CiftList text files
MEDIR="/athena/victorialab/scratch/hob4003/ME_Pipeline/MEF-P-HB/MultiEchofMRI-Pipeline" # main pipeline scripts dir
AromaPyDir="/athena/victorialab/scratch/hob4003/ME_Pipeline/ICA-AROMA-master" # path to original ICA-AROMA install dir (where ICA_AROMA.py is located)
CiftiConfigDir="$MEDIR/EVO_config" # CIFTI config dir (where CiftiList text files are saved)
KernelSize="$CiftiConfigDir"/KernelSize.txt # dimensions of kernel (cm) for smoothing/projection onto surface; can list multiple sizes and see which is better?
FSDir="$MEDIR/res0urces/FS" # dir with FreeSurfer (FS) atlases 
FSLDir="$MEDIR/res0urces/FSL" # dir with FSL (FSL) atlases

# IMPORTANT: set /paths/to/CiftiLists.txt files before running
CiftiListMGTR="NONE" # txt file list of filenames on which to perform MGTR before ICA-AROMA (use if you intend to skip ICA-AROMA entirely)
CiftiListFirstSurf="$CiftiConfigDir"/EVO_CiftiList_ICAAROMA.txt # tf list of files on which to perform MGTR after ICA-AROMA (adjust filenames if not running ICA-AROMA)
CiftiListSecondSurf="$CiftiConfigDir"/EVO_CiftiList_ICAAROMA+FirstSurf.txt # tf list of files to be smoothed and mapped to second surface; can specify OCME, OCME+MEICA, OCME+MEICA+MGTR, and/or OCME+MEICA+MGTR_Betas


# ---------------------- Environment Setup ----------------------

# Load modules & identify which session to start with
if [ -z "$4" ]
	then
	    StartSession=1
	else
	    StartSession=$4
fi

module load Connectome_Workbench/1.5.0/Connectome_Workbench
module load freesurfer/6.0.0
module load fsl/6.0.4
module load afni/afni
module load python-3.7.7-gcc-8.2.0-onbczx6
module load ants-2.4.0-gcc-8.2.0-ehibrhi
module load matlab/R2021a

# reformat subject folder path
if [ "${StudyFolder: -1}" = "/" ]; then
	StudyFolder=${StudyFolder%?};
fi

# define subject directory
Subdir="$StudyFolder"/"$Subject"
echo -e "Subdir test: $Subdir"

# These variables should not be changed unless you have a very good reason
DOF=6 # this is the degrees of freedom (DOF) used for SBref --> T1w and EPI --> SBref coregistrations
AtlasTemplate="$MEDIR/res0urces/FSL/MNI152_T1_2mm_brain.nii.gz" # define a lowres MNI template
AtlasSpace="T1w" # define either native space ("T1w") or MNI space ("MNINonlinear")

EnvironmentScript="/athena/victorialab/scratch/hob4003/ME_Pipeline/Hb_HCP_master/Examples/Scripts/SetUpHCPPipeline.sh" # Pipeline environment script
source $EnvironmentScript	# Set up pipeline environment variables and software
PATH=$PATH:/usr/lib/python2.7/site-packages # This may not be necessary if python2.7 pkgs are already on your env path; had to add for EVO

# ---------------------- Begin Denoising Pipeline ----------------------

echo -e "\nSingle-Echo Preprocessing & Denoising Pipeline\n"

# Run ICA-AROMA for motion correction and artifact identification
# NOTE: no CiftiList needed at this first step; inputs are just the results of the functional preproc pipeline
if [ $RunICAAROMA == true ]; then
	echo -e "\n$Subject: Identification & removal of artifacts via ICA-AROMA\n"
	"$MEDIR"/ICAAROMA_SE_denoise_EVOrest.sh "$MEDIR" "$Subject" "$StudyFolder" "$AtlasTemplate" "$DOF" "$NTHREADS" "$StartSession" "$AromaPyDir"
fi

# Run MGTR to smooth spatially-diffuse noise using gray-ordinates (PI's decided not to run for EVO)
# NOTE: need a CiftiList here; should be filenames on which to run MGTR
if [ $RunMGTR == true ]; then
	echo -e "\n$Subject: Removal of spatially diffuse noise via MGTR\n"
	"$MEDIR"/func_denoise_mgtr_SE_EVOrest.sh "$Subject" "$StudyFolder" "$MEDIR" "$CiftiListMGTR"
fi

# Perform signal-decay denoising and project denoised volumes onto a surface
# NOTE: need a CiftiList here; should be filenames on which to run func_vol2surf.sh
if [ $Vol2FirstSurf == true ]; then
	echo -e "\n$Subject: Signal-decay denoising and projection onto a surface\n"
	"$MEDIR"/func_vol2surf_EVOrest.sh "$Subject" "$StudyFolder" "$MEDIR" "$CiftiListFirstSurf" "$StartSession" "$FSDir" "$FSLDir"
fi

# Additional smoothing before projecting onto another surface
# NOTE: need a CiftiList here; should be filenames on which to run func_smooth.sh
if [ $SmoothVol2SecondSurf == true ]; then
	echo -e "\n$Subject: Additional smoothing and projection onto a surface\n"
	"$MEDIR"/func_smooth_EVOrest.sh "$Subject" "$StudyFolder" "$KernelSize" "$CiftiListSecondSurf"
fi

echo -e "\n$Subject: Single-echo denoising pipeline complete.\n"