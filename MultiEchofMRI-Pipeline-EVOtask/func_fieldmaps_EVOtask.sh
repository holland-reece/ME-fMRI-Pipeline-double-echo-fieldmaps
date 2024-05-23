#!/bin/bash
# Chuck Lynch, Hussain Bukhari, Holland Brown
# Pre-process field maps for EVO data from NKI collection site
# Updated 2023-12-11

MEDIR=$1
Subject=$2
StudyFolder=$3
Subdir="$StudyFolder"/"$Subject"
SUBJECTS_DIR="$Subdir"/anat/T1w # note: this is used for "bbregister" calls;
NTHREADS=$4
StartSession=$5
TaskName=$6

module load Connectome_Workbench/1.5.0/Connectome_Workbench
module load freesurfer/6.0.0
module load python-3.7.7-gcc-8.2.0-onbczx6
module load fsl/6.0.4
module load afni/afni
module load ants-2.4.0-gcc-8.2.0-ehibrhi
module load matlab/R2021a 

# If text files already exist, remove older versions
if [ -f "$Subdir"/func/"$TaskName"/qa/AvgFieldMap.txt ]; then
    echo -e "Removing old AvgFieldMap text file..."
    rm "$Subdir"/func/"$TaskName"/qa/AvgFieldMap.txt
fi
if [ -f /func/field_maps/acqparams.txt ]; then
    echo -e "Removing old acqparams text file..."
    rm "$Subdir"/func/field_maps/acqparams.txt
fi

# Create fresh xfms & qa dirs
if [ ! -d "$StudyFolder/$Subject/func/xfms/$TaskName" ]; then
	mkdir "$StudyFolder"/"$Subject"/func/xfms/"$TaskName"
else
	rm -rf "$StudyFolder/$Subject/func/xfms/$TaskName" # fresh xfms task dir
	mkdir "$StudyFolder"/"$Subject"/func/xfms/"$TaskName"
fi
if [ ! -d "$StudyFolder/$Subject/func/$TaskName/qa" ]; then
	mkdir "$StudyFolder"/"$Subject"/func/"$TaskName/qa"
else
	rm -rf "$StudyFolder"/"$Subject"/func/"$TaskName/qa" # fresh qa task dir
	mkdir "$StudyFolder"/"$Subject"/func/"$TaskName/qa"
fi

# Fresh workspace dir
rm -rf "$Subdir"/workspace/   
mkdir "$Subdir"/workspace/

# create a temp "find_fm_params.m"
cp -rf "$MEDIR"/res0urces/find_fm_params_EVO"$TaskName".m "$Subdir"/workspace/temp.m
echo -e "\nRunning Matlab script find_fm_params_EVO$TaskName...\n"

# define some Matlab variables
echo "addpath(genpath('${MEDIR}'))" | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp.m && mv "$Subdir"/workspace/tmp.m "$Subdir"/workspace/temp.m 
echo Subdir=["'$Subdir'"] | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp1.m && mv "$Subdir"/workspace/tmp1.m "$Subdir"/workspace/temp.m
echo StartSession="$StartSession" | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp2.m && mv "$Subdir"/workspace/tmp2.m "$Subdir"/workspace/temp.m 		
cd "$Subdir"/workspace/ # run script via Matlab 

echo -e "\n\t------------------------------------------------------------------------"
echo -e "\t$Subject Func Fieldmaps Matlab script (1 of 1): find_fm_params_EVO$TaskName"
echo -e "\t------------------------------------------------------------------------\n"
matlab -nodesktop -nosplash -r "temp; exit"
echo -e "\n\t----------------------------------------------"
echo -e "\t$Subject find_fm_params_EVO$TaskName Complete"
echo -e "\t----------------------------------------------\n" 

# fresh workspace
cd "$Subdir"
rm -r "$Subdir"/workspace/
mkdir "$Subdir"/workspace/

# define & create a temporary directory
mkdir -p "$Subdir"/func/"$TaskName"/AverageSBref
WDIR="$Subdir"/func/"$TaskName"/AverageSBref

# count the number of sessions
sessions=("$Subdir"/func/unprocessed/task/"$TaskName"/session_*)
sessions=$(seq 1 1 "${#sessions[@]}")

# sweep the sessions
for s in $sessions ; do

	# count number of runs for this session
	runs=("$Subdir"/func/unprocessed/task/"$TaskName"/session_"$s"/run_*)
	runs=$(seq 1 1 "${#runs[@]}")

	# sweep the runs
	for r in $runs ; do

		# check to see if this file exists or not
		if [ -f "$Subdir"/func/unprocessed/field_maps/FM_rads_S"$s"_R"$r".nii.gz ]; then

			# the "AllFMs.txt" file contains 
			# dir. paths to every pair of field maps
            if [ -f "$Subdir"/AllFMs.txt ]; then
                rm "$Subdir"/AllFMs.txt
            fi
			touch "$Subdir"/AllFMs.txt
			echo S"$s"_R"$r" >> "$Subdir"/AllFMs.txt  

		fi

	done

done

# DON'T RUN THIS PART FOR TASK (ALREADY PREPROCESSED FIELDMAPS DURING REST PREPROC) --------------------------------

# # define a list of directories
# AllFMs=$(cat "$Subdir"/AllFMs.txt)
# rm "$Subdir"/AllFMs.txt # remove intermediate file

# # create a white matter segmentation (.mgz --> .nii.gz)
# mri_binarize --i "$Subdir"/anat/T1w/"$Subject"/mri/aparc+aseg.mgz --wm --o "$Subdir"/anat/T1w/"$Subject"/mri/white.mgz
# mri_convert -i "$Subdir"/anat/T1w/"$Subject"/mri/white.mgz -o "$Subdir"/anat/T1w/"$Subject"/mri/white.nii.gz --like "$Subdir"/anat/T1w/T1w_acpc_dc_restore.nii.gz  # create a white matter segmentation (.mgz --> .nii.gz);

# # create clean tmp. copy of freesurfer folder
# rm -rf "$Subdir"/anat/T1w/freesurfer   
# cp -rf "$Subdir"/anat/T1w/"$Subject" "$Subdir"/anat/T1w/freesurfer

# # create & define the FM "library"
# rm -rf "$Subdir"/func/field_maps/AllFMs  
# mkdir -p "$Subdir"/func/field_maps/AllFMs  
# WDIR="$Subdir"/func/field_maps/AllFMs

# for ThisFM in $AllFMs
# do

#     echo $ThisFM

#     # copy over field map pair to workspace 
#     cp -r "$Subdir"/func/unprocessed/field_maps/FM_rads_"$ThisFM".nii.gz "$WDIR"/FM_rads_"$ThisFM".nii.gz
#     cp -r "$Subdir"/func/unprocessed/field_maps/FM_mag_"$ThisFM".nii.gz "$WDIR"/FM_mag_"$ThisFM".nii.gz

#     # temporary bet image (for EVO, this only needs to be run for UW participants)
#     # cp -r "$Subdir"/func/unprocessed/field_maps/FM_mag_brain_"$ThisFM".nii.gz "$WDIR"/FM_mag_brain_"$ThisFM".nii.gz # added for EVO NKI data (already ran bet)
#     bet "$WDIR"/FM_mag_"$ThisFM".nii.gz "$WDIR"/FM_mag_brain_"$ThisFM".nii.gz -f 0.6 -B  
#     cp -r "$WDIR"/FM_mag_brain_"$ThisFM".nii.gz "$Subdir"/func/unprocessed/field_maps # save a copy in unproc dir

#     # **ADD HERE LATER: for future use, add call to my preproc_fieldmaps script here (ran it outside of pipeline for EVO)**

#     # register reference volume to the T1-weighted anatomical image; use bbr cost function 
#     epi_reg --epi="$WDIR"/FM_mag_"$ThisFM".nii.gz --t1="$Subdir"/anat/T1w/T1w_acpc_dc_restore.nii.gz \
#     --t1brain="$Subdir"/anat/T1w/T1w_acpc_dc_restore_brain.nii.gz --out="$WDIR"/fm2acpc_"$ThisFM" --wmseg="$Subdir"/anat/T1w/"$Subject"/mri/white.nii.gz --dof=6   

#     # use BBRegister to fine-tune the existing co-registration; output FSL style transformation matrix; (not sure why --s isnt working, renaming dir. to "freesurfer" as an ugly workaround)
#     bbregister --s freesurfer --mov "$WDIR"/fm2acpc_"$ThisFM".nii.gz --init-reg "$MEDIR"/res0urces/FSL/eye.dat --surf white.deformed --bold --reg "$WDIR"/fm2acpc_bbr_"$ThisFM".dat --6 --o "$WDIR"/fm2acpc_bbr_"$ThisFM".nii.gz 
#     tkregister2 --s freesurfer --noedit --reg "$WDIR"/fm2acpc_bbr_"$ThisFM".dat --mov "$WDIR"/fm2acpc_"$ThisFM".nii.gz --targ "$Subdir"/anat/T1w/T1w_acpc_dc_restore.nii.gz --fslregout "$WDIR"/fm2acpc_bbr_"$ThisFM".mat 

#     # combine the original and fine tuned affine matrix
#     convert_xfm -omat "$WDIR"/fm2acpc_"$ThisFM".mat \
#     -concat "$WDIR"/fm2acpc_bbr_"$ThisFM".mat \
#     "$WDIR"/fm2acpc_"$ThisFM".mat  

#     # apply transformation to the relevant files
#     flirt -dof 6 -interp spline -in "$WDIR"/FM_mag_"$ThisFM".nii.gz -ref "$Subdir"/anat/T1w/T1w_acpc_dc_restore_brain.nii.gz -out "$WDIR"/FM_mag_acpc_"$ThisFM".nii.gz -applyxfm -init "$WDIR"/fm2acpc_"$ThisFM".mat 
#     fslmaths "$WDIR"/FM_mag_acpc_"$ThisFM".nii.gz -mas "$Subdir"/anat/T1w/T1w_acpc_dc_restore_brain.nii.gz "$WDIR"/FM_mag_acpc_brain_"$ThisFM".nii.gz  
#     flirt -dof 6 -interp spline -in "$WDIR"/FM_rads_"$ThisFM".nii.gz -ref "$Subdir"/anat/T1w/T1w_acpc_dc_restore_brain.nii.gz -out "$WDIR"/FM_rads_acpc_"$ThisFM".nii.gz -applyxfm -init "$WDIR"/fm2acpc_"$ThisFM".mat 
#     wb_command -volume-smoothing "$WDIR"/FM_rads_acpc_"$ThisFM".nii.gz 2 "$WDIR"/FM_rads_acpc_"$ThisFM".nii.gz -fix-zeros   

# done

# # This section is repeated in post_func_preproc_fm.sh (only run once)
# # merge & average the co-registered field map images accross sessions
# fslmerge -t "$Subdir"/func/field_maps/Avg_FM_rads_acpc.nii.gz "$WDIR"/FM_rads_acpc_S*.nii.gz 
# fslmaths "$Subdir"/func/field_maps/Avg_FM_rads_acpc.nii.gz -Tmean "$Subdir"/func/field_maps/Avg_FM_rads_acpc.nii.gz 
# fslmerge -t "$Subdir"/func/field_maps/Avg_FM_mag_acpc.nii.gz "$WDIR"/FM_mag_acpc_S*.nii.gz 
# fslmaths "$Subdir"/func/field_maps/Avg_FM_mag_acpc.nii.gz -Tmean "$Subdir"/func/field_maps/Avg_FM_mag_acpc.nii.gz 

# # perform a final brain extraction
# fslmaths "$Subdir"/func/field_maps/Avg_FM_mag_acpc.nii.gz -mas "$Subdir"/anat/T1w/T1w_acpc_dc_restore_brain.nii.gz \
# "$Subdir"/func/field_maps/Avg_FM_mag_acpc_brain.nii.gz 
# rm -rf "$Subdir"/anat/T1w/freesurfer/ # remove softlink
