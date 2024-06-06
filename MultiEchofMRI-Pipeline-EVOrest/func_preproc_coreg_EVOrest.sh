#!/bin/bash
# Charles Lynch, Holland Brown
# Create SBrefs (if necessary) and coregister to anatomicals
# Updated 2023-09-11

MEDIR=$1
Subject=$2
StudyFolder=$3
Subdir="$StudyFolder"/"$Subject"
SUBJECTS_DIR="$Subdir"/anat/T1w # note: this is used for "bbregister" calls
AtlasTemplate=$4
DOF=$5
NTHREADS=$6
StartSession=$7 # adjust call to script in wrapper

module load Connectome_Workbench/1.5.0/Connectome_Workbench
module load freesurfer/6.0.0
module load python-3.7.7-gcc-8.2.0-onbczx6
module load fsl/6.0.4
module load afni/afni
module load ants-2.4.0-gcc-8.2.0-ehibrhi
module load matlab/R2021a

# First, lets read in all the .json files associated with each scan & write out some .txt files that will be used during preprocessing

# fresh workspace dir.
rm -rf "$Subdir"/workspace  
mkdir "$Subdir"/workspace  

# create temporary find_epi_params.m 
cp -rf "$MEDIR"/res0urces/find_epi_params_EVO.m "$Subdir"/workspace
mv "$Subdir"/workspace/find_epi_params_EVO.m "$Subdir"/workspace/temp.m # rename in a separate line

# define some Matlab variables;
echo "addpath(genpath('${MEDIR}'))" | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp.m && mv "$Subdir"/workspace/tmp.m "$Subdir"/workspace/temp.m
echo Subdir=["'$Subdir'"] | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp1.m && mv "$Subdir"/workspace/tmp1.m "$Subdir"/workspace/temp.m	
echo FuncName=["'rest'"] | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp2.m && mv "$Subdir"/workspace/tmp2.m "$Subdir"/workspace/temp.m  		
echo StartSession="$StartSession" | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp3.m && mv "$Subdir"/workspace/tmp3.m "$Subdir"/workspace/temp.m
cd "$Subdir"/workspace/ # run script via Matlab 
matlab -nodesktop -nosplash -r "temp; exit"

# delete some files
cd "$Subdir" # go back to subject dir.
rm -rf "$Subdir"/workspace/
mkdir "$Subdir"/workspace/

# next, we loop through all scans and create SBrefs (average of first few echoes) for each scan
# NOTE: this is used (when needed) as an intermediate target for co-registeration

# define & create a temporary directory;
mkdir -p "$Subdir"/func/rest/AverageSBref/
WDIR="$Subdir"/func/rest/AverageSBref/

# count the number of sessions
sessions=("$Subdir"/func/unprocessed/rest/session_*)
sessions=$(seq 1 1 "${#sessions[@]}")

# sweep through sessions 
for s in $sessions ; do

	# count number of runs for this session;
	runs=("$Subdir"/func/unprocessed/rest/session_"$s"/run_*)
	runs=$(seq 1 1 "${#runs[@]}")

	# sweep the runs;
	for r in $runs ; do 

		# define the echo times;
		te=$(cat "$Subdir"/func/rest/session_"$s"/run_"$r"/TE.txt)
		n_te=0 # set to zero;

		# sweep the te;
		for i in $te ; do

			# keep track of 
			# which te we are on;
			n_te=`expr $n_te + 1` 

			# if there is no single-band reference image, we can assume that there 
			# are also a bunch of non-steady state images we need to dump from the start of the time-series...
			if [[ ! -f "$Subdir"/func/unprocessed/rest/session_"$s"/run_"$r"/SBref_S"$s"_R"$r"_E"$n_te".nii.gz ]]; then
				fslroi "$Subdir"/func/unprocessed/rest/session_"$s"/run_"$r"/Rest_S"$s"_R"$r"_E"$n_te".nii.gz "$Subdir"/func/unprocessed/rest/session_"$s"/run_"$r"/SBref_S"$s"_R"$r"_E"$n_te".nii.gz 10 1 
				echo 10 > "$Subdir"/func/rest/session_"$s"/run_"$r"/rmVols.txt
			fi

		done

		# use the first echo (w/ least amount of signal dropout) to estimate bias field;
		cp "$Subdir"/func/unprocessed/rest/session_"$s"/run_"$r"/SBref*_E1.nii.gz "$WDIR"/TMP_1.nii.gz
		
		# estimate field inhomog. & resample bias field image (ANTs --> FSL orientation);
		N4BiasFieldCorrection -d 3 -i "$WDIR"/TMP_1.nii.gz -o ["$WDIR"/TMP_restored.nii.gz,"$WDIR"/Bias_field_"$s"_"$r".nii.gz] # CHANGED: spaces in brackets were causing a parsing error
		flirt -in "$WDIR"/Bias_field_"$s"_"$r".nii.gz -ref "$WDIR"/TMP_1.nii.gz -applyxfm -init "$MEDIR"/res0urces/ident.mat -out "$WDIR"/Bias_field_"$s"_"$r".nii.gz -interp spline

		# set back 
		# to zero;
		n_te=0 

		# sweep the te;
		for i in $te ; do

			# skip the "long" te;
			if [[ $i < 60 ]] ; then 

				n_te=`expr $n_te + 1` # keep track which te we are on;
				cp "$Subdir"/func/unprocessed/rest/session_"$s"/run_"$r"/SBref*_E"$n_te.nii".gz "$WDIR"/TMP_"$n_te".nii.gz
				fslmaths "$WDIR"/TMP_"$n_te".nii.gz -div "$WDIR"/Bias_field_"$s"_"$r".nii.gz "$WDIR"/TMP_"$n_te".nii.gz # apply correction;

			fi

		done

		# combine & average the te; 
		fslmerge -t "$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz "$WDIR"/TMP_*.nii.gz   
		fslmaths "$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz -Tmean "$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz
		cp "$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz "$WDIR"/SBref_"$s"_"$r".nii.gz
		rm "$WDIR"/TMP* # remove intermediate files;

	done

done

# Co-register all SBrefs and create an average SBref for cross-scan allignment 

# build a list of all SBrefs;
images=("$WDIR"/SBref_*.nii.gz)

# count images; average if needed  
if [ "${#images[@]}" \> 1 ]; then

	# align  and average the single-band reference (SBref) images;
	"$MEDIR"/res0urces/FuncAverage -n -o "$Subdir"/func/xfms/rest/AvgSBref.nii.gz "$WDIR"/SBref_*.nii.gz   

else

	# copy over the lone single-band reference (SBref) image;
	cp "${images[0]}" "$Subdir"/func/xfms/rest/AvgSBref.nii.gz  

fi

# create clean tmp. copy of freesurfer folder;
rm -rf "$Subdir"/anat/T1w/freesurfer  
cp -rf "$Subdir"/anat/T1w/"$Subject" "$Subdir"/anat/T1w/freesurfer  

# define the effective echo spacing;
EchoSpacing=$(cat $Subdir/func/xfms/rest/EffectiveEchoSpacing.txt) 

# use BBRegister (BBR) to fine-tune the existing co-registration & output FSL style transformation matrix
# CHECK: is this registering to T1w or MNI?
# CHECK: inputs/outputs and purpose of tkregister2
# Outputs: AvgSBref2acpc_EpiReg+BBR.nii.gz (functional NIFTI registered to prev reg?), --dat AvgSBref2acpc_EpiReg+BBR.dat; Input: --mov AvgSBref2acpc_EpiReg.nii.gz (?)

# register average SBref image to T1-weighted anatomical image using FSL's EpiReg (correct for spatial distortions using average field map); 
"$MEDIR"/res0urces/epi_reg_dof --dof="$DOF" --epi="$Subdir"/func/xfms/rest/AvgSBref.nii.gz --t1="$Subdir"/anat/T1w/T1w_acpc_dc_restore.nii.gz --t1brain="$Subdir"/anat/T1w/T1w_acpc_dc_restore_brain.nii.gz --out="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg --fmap="$Subdir"/func/field_maps/Avg_FM_rads_acpc.nii.gz --fmapmag="$Subdir"/func/field_maps/Avg_FM_mag_acpc.nii.gz --fmapmagbrain="$Subdir"/func/field_maps/Avg_FM_mag_acpc_brain.nii.gz --echospacing="$EchoSpacing" --wmseg="$Subdir"/anat/T1w/"$Subject"/mri/white.nii.gz --nofmapreg --pedir=-y   # note: need to manually set --pedir

applywarp --interp=spline --in="$Subdir"/func/xfms/rest/AvgSBref.nii.gz --ref="$AtlasTemplate" --out="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg.nii.gz --warp="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg_warp.nii.gz

# use BBRegister (BBR) to fine-tune the existing co-registration & output FSL style transformation matrix;
bbregister --s freesurfer --mov "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg.nii.gz --init-reg "$MEDIR"/res0urces/eye.dat --surf white.deformed --bold --reg "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR.dat --6 --o "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR.nii.gz   
tkregister2 --s freesurfer --noedit --reg "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR.dat --mov "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg.nii.gz --targ "$Subdir"/anat/T1w/T1w_acpc_dc_restore.nii.gz --fslregout "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR.mat   

# add BBR step as post warp linear transformation & generate inverse warp;
convertwarp --warp1="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg_warp.nii.gz --postmat="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR.mat --ref="$AtlasTemplate" --out="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR_warp.nii.gz
applywarp --interp=spline --in="$Subdir"/func/xfms/rest/AvgSBref.nii.gz --ref="$AtlasTemplate" --out="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR.nii.gz --warp="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR_warp.nii.gz
invwarp --ref="$Subdir"/func/xfms/rest/AvgSBref.nii.gz -w "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR_warp.nii.gz -o "$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR_inv_warp.nii.gz # invert func --> T1w anatomical warp; includ. dc.;

# combine warps (distorted SBref image --> T1w_acpc & anatomical image in acpc --> MNI atlas)
convertwarp --ref="$AtlasTemplate" --warp1="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR_warp.nii.gz --warp2="$Subdir"/anat/MNINonLinear/xfms/acpc_dc2standard.nii.gz --out="$Subdir"/func/xfms/rest/AvgSBref2nonlin_EpiReg+BBR_warp.nii.gz
applywarp --interp=spline --in="$Subdir"/func/xfms/rest/AvgSBref.nii.gz --ref="$AtlasTemplate" --out="$Subdir"/func/xfms/rest/AvgSBref2nonlin_EpiReg+BBR.nii.gz --warp="$Subdir"/func/xfms/rest/AvgSBref2nonlin_EpiReg+BBR_warp.nii.gz
invwarp -w "$Subdir"/func/xfms/rest/AvgSBref2nonlin_EpiReg+BBR_warp.nii.gz -o "$Subdir"/func/xfms/rest/AvgSBref2nonlin_EpiReg+BBR_inv_warp.nii.gz --ref="$Subdir"/func/xfms/rest/AvgSBref.nii.gz # generate an inverse warp; atlas --> distorted SBref image 

# now, lets also co-register individual SBrefs to the target anatomical image;
# NOTE: we will compare which is best (avg. field map vs. scan-specific) later on

# create & define the "CoregQA" folder;
mkdir -p "$Subdir"/func/qa/CoregQA  

# count the number of sessions
Sessions=("$Subdir"/func/rest/session_*)
Sessions=$(seq $StartSession 1 "${#sessions[@]}")

# func ---------------------------------------------------------------
# sweep through sessions 
for s in $Sessions ; do

	# count number of runs for this session;
	runs=("$Subdir"/func/rest/session_"$s"/run_*)
	runs=$(seq 1 1 "${#runs[@]}")

	# sweep the runs
	for r in $runs ; do

		# check to see if this scan has a field map or not
		if [[ -f "$Subdir/func/field_maps/AllFMs/FM_rads_acpc_S"$s"_R"$r".nii.gz" ]]; then # this needs to have spaces around brackets

			# define the effective echo spacing
			EchoSpacing=$(cat "$Subdir"/func/rest/session_"$s"/run_"$r"/EffectiveEchoSpacing.txt) 
		
			# register average SBref image to T1-weighted anatomical image using FSL's EpiReg (correct for spatial distortions using scan-specific field map);
			# NOTE: need to manually set --pedir (phase encoding direction)
			"$MEDIR"/res0urces/epi_reg_dof --dof="$DOF" --epi="$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz --t1="$Subdir"/anat/T1w/T1w_acpc_dc_restore.nii.gz --t1brain="$Subdir"/anat/T1w/T1w_acpc_dc_restore_brain.nii.gz --out="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg_S"$s"_R"$r" --fmap="$Subdir"/func/field_maps/AllFMs/FM_rads_acpc_S"$s"_R"$r".nii.gz --fmapmag="$Subdir"/func/field_maps/AllFMs/FM_mag_acpc_S"$s"_R"$r".nii.gz --fmapmagbrain="$Subdir"/func/field_maps/AllFMs/FM_mag_acpc_brain_S"$s"_R"$r".nii.gz --echospacing="$EchoSpacing" --wmseg="$Subdir"/anat/T1w/"$Subject"/mri/white.nii.gz --nofmapreg --pedir=-y  
			applywarp --interp=spline --in="$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz --ref="$AtlasTemplate" --out="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg_S"$s"_R"$r".nii.gz --warp="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg_S"$s"_R"$r"_warp.nii.gz

			# use BBRegister (BBR) to fine-tune the existing co-registeration; output FSL style transformation matrix
			bbregister --s freesurfer --mov "$Subdir"/func/xfms/rest/SBref2acpc_EpiReg_S"$s"_R"$r".nii.gz --init-reg "$MEDIR"/res0urces/eye.dat --surf white.deformed --bold --reg "$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r".dat --6 --o "$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r".nii.gz   
			tkregister2 --s freesurfer --noedit --reg "$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r".dat --mov "$Subdir"/func/xfms/rest/SBref2acpc_EpiReg_S"$s"_R"$r".nii.gz --targ "$Subdir"/anat/T1w/T1w_acpc_dc_restore.nii.gz --fslregout "$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r".mat   

			# add BBR step as post warp linear transformation & generate inverse warp
			convertwarp --warp1="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg_S"$s"_R"$r"_warp.nii.gz --postmat="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r".mat --ref="$AtlasTemplate" --out="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r"_warp.nii.gz
			applywarp --interp=spline --in="$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz --ref="$AtlasTemplate" --out="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r".nii.gz --warp="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r"_warp.nii.gz
			mv "$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r".nii.gz "$Subdir"/func/qa/CoregQA/SBref2acpc_EpiReg+BBR_ScanSpecificFM_S"$s"_R"$r".nii.gz
			
			# warp SBref image into MNI atlas volume space in a single spline warp; can be used for CoregQA
			convertwarp --ref="$AtlasTemplate" --warp1="$Subdir"/func/xfms/rest/SBref2acpc_EpiReg+BBR_S"$s"_R"$r"_warp.nii.gz --warp2="$Subdir"/anat/MNINonLinear/xfms/acpc_dc2standard.nii.gz --out="$Subdir"/func/xfms/rest/SBref2nonlin_EpiReg+BBR_S"$s"_R"$r"_warp.nii.gz
			applywarp --interp=spline --in="$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz --ref="$AtlasTemplate" --out="$Subdir"/func/qa/CoregQA/SBref2nonlin_EpiReg+BBR_ScanSpecificFM_S"$s"_R"$r".nii.gz --warp="$Subdir"/func/xfms/rest/SBref2nonlin_EpiReg+BBR_S"$s"_R"$r"_warp.nii.gz

		fi

		# repeat warps (ACPC, MNI) but this time with the native --> acpc co-registration using an average field map;
		flirt -dof "$DOF" -in "$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz -ref "$Subdir"/func/xfms/rest/AvgSBref.nii.gz -out "$Subdir"/func/qa/CoregQA/SBref2AvgSBref_S"$s"_R"$r".nii.gz -omat "$Subdir"/func/qa/CoregQA/SBref2AvgSBref_S"$s"_R"$r".mat
		applywarp --interp=spline --in="$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz --premat="$Subdir"/func/qa/CoregQA/SBref2AvgSBref_S"$s"_R"$r".mat --warp="$Subdir"/func/xfms/rest/AvgSBref2acpc_EpiReg+BBR_warp.nii.gz --out="$Subdir"/func/qa/CoregQA/SBref2acpc_EpiReg+BBR_AvgFM_S"$s"_R"$r".nii.gz --ref="$AtlasTemplate"
		applywarp --interp=spline --in="$Subdir"/func/rest/session_"$s"/run_"$r"/SBref.nii.gz --premat="$Subdir"/func/qa/CoregQA/SBref2AvgSBref_S"$s"_R"$r".mat --warp="$Subdir"/func/xfms/rest/AvgSBref2nonlin_EpiReg+BBR_warp.nii.gz --out="$Subdir"/func/qa/CoregQA/SBref2nonlin_EpiReg+BBR_AvgFM_S"$s"_R"$r".nii.gz --ref="$AtlasTemplate"

	done

done

# END FUNCTION ----------------------------------------------------------

# finally, lets create files that will be needed later on (brain mask and subcortical mask in functional space)

# generate a set of functional brain mask (acpc + nonlin) in the atlas space; 
flirt -interp nearestneighbour -in "$Subdir"/anat/T1w/T1w_acpc_dc_brain.nii.gz -ref "$AtlasTemplate" -out "$Subdir"/func/xfms/rest/T1w_acpc_brain_func.nii.gz -applyxfm -init "$MEDIR"/res0urces/ident.mat
flirt -interp nearestneighbour -in "$Subdir"/anat/T1w/T1w_acpc_brain_mask.nii.gz -ref "$AtlasTemplate" -out "$Subdir"/func/xfms/rest/T1w_acpc_brain_func_mask.nii.gz -applyxfm -init "$MEDIR"/res0urces/ident.mat
flirt -interp nearestneighbour -in "$Subdir"/anat/MNINonLinear/T1w_restore_brain.nii.gz -ref "$AtlasTemplate" -out "$Subdir"/func/xfms/rest/T1w_nonlin_brain_func.nii.gz -applyxfm -init "$MEDIR"/res0urces/ident.mat # anat in std space transformed to functional atlas space;
fslmaths "$Subdir"/func/xfms/rest/T1w_nonlin_brain_func.nii.gz -bin "$Subdir"/func/xfms/rest/T1w_nonlin_brain_func_mask.nii.gz # this is a binarized version of the T1w_nonlin_brain.nii.gz image in 2mm atlas space; used for masking functional data

# remove tmp. freesurfer folder
rm -rf "$Subdir"/anat/T1w/freesurfer

# fresh workspace dir
rm -rf "$Subdir"/workspace  
mkdir "$Subdir"/workspace  

# create temp. make_precise_subcortical_labels.m 
cp -rf "$MEDIR"/res0urces/make_precise_subcortical_labels_EVO.m "$Subdir"/workspace/temp.m

# make tmp dir and navigate there (bug fix for make_precise_subcortical_labels_EVO.m; can't make dirs due to permissions)
mkdir "$Subdir"/func/rois/tmp
mkdir "$Subdir"/func/rois/tmp_nonlin

# define some Matlab variables
echo "addpath(genpath('${MEDIR}'))" | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp.m && mv "$Subdir"/workspace/tmp.m "$Subdir"/workspace/temp.m
echo Subdir=["'$Subdir'"] | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp1.m && mv "$Subdir"/workspace/tmp1.m "$Subdir"/workspace/temp.m	
echo AtlasTemplate=["'$AtlasTemplate'"] | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp2.m && mv "$Subdir"/workspace/tmp2.m "$Subdir"/workspace/temp.m	
echo SubcorticalLabels=["'$MEDIR/res0urces/FS/SubcorticalLabels.txt'"] | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp3.m && mv "$Subdir"/workspace/tmp3.m "$Subdir"/workspace/temp.m		
cd "$Subdir"/workspace/ # run script via Matlab 
matlab -nodesktop -nosplash -r "temp; exit" 
cd "$Subdir" # go back to subject dir

# remove temp dirs (bug fix for make_precise_subcortical_labels_EVO.m; can't remove dirs due to permissions)
rm -rf "$Subdir"/func/rois/tmp/
rm -rf "$Subdir"/func/rois/tmp_nonlin/

# finally, evaluate whether scan-specific or average field maps 
# produce the best co-registeration/cross-scan allignment & 
# then generate a movie summarizing the results 

# fresh workspace dir.
rm -rf "$Subdir"/workspace/
mkdir "$Subdir"/workspace/

# create temporary CoregQA.m 
cp -rf "$MEDIR"/res0urces/coreg_qa.m "$Subdir"/workspace/temp.m

# define some Matlab variables
echo "addpath(genpath('${MEDIR}'))" | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp.m && mv "$Subdir"/workspace/tmp.m "$Subdir"/workspace/temp.m
echo Subdir=["'$Subdir'"] | cat - "$Subdir"/workspace/temp.m >> "$Subdir"/workspace/tmp1.m && mv "$Subdir"/workspace/tmp1.m "$Subdir"/workspace/temp.m		
cd "$Subdir"/workspace/ # run script via Matlab 
matlab -nodesktop -nosplash -r "temp; exit"
rm -rf "$Subdir"/workspace
cd "$Subdir" # go back to subject dir