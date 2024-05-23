# Liston-Laboratory-MultiEchofMRI-Pipeline
Repository for "Rapid precision mapping of individuals using multi-echo fMRI" ; Lynch et al. 2020 Cell Reports.

This pipeline was designed to process longitudinal multi-echo fMRI data. It calls scripts developed by the Human Connectome Project (for preprocessing of high resolution anatomical images and the generation of cortical surfaces) and Tedana (for signal-decay based denoising). 

Important Note: Code and instructions for use will be updated on a rolling basis to ensure generalizability of code to other computing environments.

Instructions for use: Data must be organized in the expected manner (see "ExampleDataOrganization" folder). Some images must also be accompanied by .json files (which can be produced by dicom conversion programs; e.g., "dcm2niix"). The .json files will be used at various points in the functional pipeline to obtain information needed for preprocessing (echo spacing, total readout time, slice time information, etc.) and denoising (echo times, etc.). 

Required Software
- Matab
- Freesurfer 
- FSL
- Connectome Workbench 
- ANTS
- Tedana
- GNU

## Step 1: Change all relevant paths in the FreeSurfer environment set up script /SetupHCPPipelinesScript.sh
    - see FreeSurfer pipelines documentation for more information (https://github.com/Washington-University/HCPpipelines)
    - NOTE: this script is sourced in the anatomical, functional and denoising wrappers

## Step 2: Anatomical Pipeline >> /anat_highres_HCP_wrapper_par.sh
    - set up general variables
        - in script to submit cluster jobs, define study folder, subject ID, TE, magnitude fieldmap name, phase fieldmap name, number of cluster cores, and readout distortion correction
        - set path to /SetupHCPPipelinesScript.sh (variable: "EnvironmentScript")

#### (A) Pre-FreeSurfer Pipeline
        - paths to templates (likely don't need to change; paths are set during /SetupHCPPipelinesScript.sh script)
        - structural scan settings
            - check JSON files or scan protocol docs to make sure DICOM field and unwarping direction are correct
            - brain size should typically be between 150 and 170 mm; choose 170 and decrease size + re-run if brain appears warped at end
            - set path to FNIRT config file (something like /T1_2_MNI152_2mm.cnf)
        - set gradient distortion coefficients if using spin echo fieldmaps (set to "NONE" for EVO study because fieldmaps were not spin-echo)

#### (B) FreeSurfer Pipeline >> func_wrapper.sh
        - in script to submit cluster jobs, define study folder, subject ID, number of cluster cores, starting session (option to start with first session, or only run second session, for example)
        - set $MEDIR variable: path to the bash pipeline scripts and /res0urces folder where Matlab scripts are located
        - set degrees of freedom used for SBref coregistration step
        - path to atlas template
        - set $AtlasSpace: can be either native space ("T1w") or MNI space ("MNINonlinear")
        - sources /SetUpHCPPipeline.sh you set up earlier for the anatomical pipeline

#### (C) Post-FreeSurfer Pipeline

## Step 3: Functional Pipeline

##### (1) /func_fieldmaps.sh : Process all field maps & create an average image for cases where scan-specific maps are unavailable
    - NOTE: two important text documents are created in this script, AvgFieldMap.txt and acqparams.txt; I added code at the beginning to remove these if they are already there, or else script will continue to write into pre-existing ones

    >>> /res0urces/find_fm_params.m : runs matlab script that extracts scan parameter information from fieldmap json files

    - creates /AllFMs.txt file, which should contain a list of the sessions and runs for which there are fieldmaps in the format 'S1_R1'
    - brain extracts, registers, and averages fieldmaps across sessions
    - performs a final brain extraction on the averaged fieldmap image

##### (2) /func_coreg.sh : Create an avg SBref image; co-register that image & all individual SBrefs to the T1w image
    >>> /res0urces/find_epi_params.m : runs matlab script that extracts EPI (fMRI) scan parameters from json files

    - if there are no single-band reference (SBref) images, creates them from an average of the first few volumes (which have less signal dropout/drift)
    - estimates bias field (i.e. field inhomogeneities) from SBrefs to be used later

    - NOTE: uses epi_reg_dof (a customized version of FSL's epi_reg) to get echo spacing information in a specific format

    - registers all SBrefs to outputs of anatomical pipeline in /anat/T1w/freesurfer
    - averages all SBrefs together and registers the average SBref to outputs of anatomical pipeline in /anat/T1w/freesurfer
    - registers the SBrefs for each session to outputs of anatomical pipeline in /anat/T1w/freesurfer
    - evaluates whether scan-specific or averaged fieldmaps give best co-registeration/cross-scan allignment
    - generates a movie to help with QA

##### (3) /func_headmotion.sh : Correct func images for slice-time differences & head motion; motion QA









## Step 4: Denoising Pipeline
