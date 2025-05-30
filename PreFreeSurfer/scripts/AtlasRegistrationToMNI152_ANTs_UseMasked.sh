#!/bin/bash 
set -x

export OMP_NUM_THREADS=1
export PATH=`echo $PATH | sed 's|freesurfer/|freesurfer53/|g'`

# Requirements for this script
#  installed versions of: FSL (version 5.0.6)
#  environment: FSLDIR

################################################ SUPPORT FUNCTIONS ##################################################

Usage() {
  echo "`basename $0`: Tool for non-linearly registering T1w and T2w to MNI space (T1w and T2w must already be registered together)"
  echo " "
  echo "Usage: `basename $0` [--workingdir=<working dir>]"
  echo "                --t1=<t1w image>"
  echo "                --t1rest=<bias corrected t1w image>"
  echo "                --t1restbrain=<bias corrected, brain extracted t1w image>"
  echo "                --t2=<t2w image>"
  echo "                --t2rest=<bias corrected t2w image>"
  echo "                --t2restbrain=<bias corrected, brain extracted t2w image>"
  echo "                --ref=<reference image>"
  echo "                --refbrain=<reference brain image>"
  echo "                --refmask=<reference brain mask>"
  echo "                [--ref2mm=<reference 2mm image>]"
  echo "                [--ref2mmmask=<reference 2mm brain mask>]"
  echo "                --owarp=<output warp>"
  echo "                --oinvwarp=<output inverse warp>"
  echo "                --ot1=<output t1w to MNI>"
  echo "                --ot1rest=<output bias corrected t1w to MNI>"
  echo "                --ot1restbrain=<output bias corrected, brain extracted t1w to MNI>"
  echo "                --ot2=<output t2w to MNI>"
  echo "                --ot2rest=<output bias corrected t2w to MNI>"
  echo "                --ot2restbrain=<output bias corrected, brain extracted t2w to MNI>"
  echo "                [--fnirtconfig=<FNIRT configuration file>]"
  echo "                --useT2=<false if T2w image is unavailable, default is true>"
}

# function for parsing options
getopt1() {
    sopt="$1"
    shift 1
    for fn in $@ ; do
	if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
	    echo $fn | sed "s/^${sopt}=//"
	    return 0
	fi
    done
}

defaultopt() {
    echo $1
}

################################################### OUTPUT FILES #####################################################

# Outputs (in $WD):  xfms/acpc2MNILinear.mat  
#                    xfms/${T1wRestoreBrainBasename}_to_MNILinear  
#                    xfms/IntensityModulatedT1.nii.gz  xfms/NonlinearRegJacobians.nii.gz  
#                    xfms/IntensityModulatedT1.nii.gz  xfms/2mmReg.nii.gz  
#                    xfms/NonlinearReg.txt  xfms/NonlinearIntensities.nii.gz  
#                    xfms/NonlinearReg.nii.gz 
# Outputs (not in $WD): ${OutputTransform} ${OutputInvTransform}   
#                       ${OutputT1wImage} ${OutputT1wImageRestore}  
#                       ${OutputT1wImageRestoreBrain}
#                       ${OutputT2wImage}  ${OutputT2wImageRestore}  
#                       ${OutputT2wImageRestoreBrain}

################################################## OPTION PARSING #####################################################

# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi
# check for correct options
if [ $# -lt 19 ] ; then Usage; exit 1; fi

# parse arguments
WD=`getopt1 "--workingdir" $@`  # "$1"
T1wImage=`getopt1 "--t1" $@`  # "$2"
T1wRestore=`getopt1 "--t1rest" $@`  # "$3"
T1wRestoreBrain=`getopt1 "--t1restbrain" $@`  # "$4"
T2wImage=`getopt1 "--t2" $@`  # "$5"
T2wRestore=`getopt1 "--t2rest" $@`  # "$6"
T2wRestoreBrain=`getopt1 "--t2restbrain" $@`  # 
Reference=`getopt1 "--ref" $@`  # "$8"
ReferenceBrain=`getopt1 "--refbrain" $@`  # "$9"
ReferenceMask=`getopt1 "--refmask" $@`  # "${10}"
Reference2mm=`getopt1 "--ref2mm" $@`  # "${11}"
Reference2mmMask=`getopt1 "--ref2mmmask" $@`  # "${12}"
OutputTransform=`getopt1 "--owarp" $@`  # "${13}"
OutputInvTransform=`getopt1 "--oinvwarp" $@`  # "${14}"
OutputT1wImage=`getopt1 "--ot1" $@`  # "${15}"
OutputT1wImageRestore=`getopt1 "--ot1rest" $@`  # "${16}"
OutputT1wImageRestoreBrain=`getopt1 "--ot1restbrain" $@`  # "${17}"
OutputT2wImage=`getopt1 "--ot2" $@`  # "${18}"
OutputT2wImageRestore=`getopt1 "--ot2rest" $@`  # "${19}"
OutputT2wImageRestoreBrain=`getopt1 "--ot2restbrain" $@`  # "${20}"
useT2=`getopt1 "--useT2" $@` # "${22}"

# default parameters
# WD=`defaultopt $WD .`
# Reference2mm=`defaultopt $Reference2mm ${HCPPIPEDIR_Templates}/MNI152_T1_2mm.nii.gz`
# Reference2mmMask=`defaultopt $Reference2mmMask ${HCPPIPEDIR_Templates}/MNI152_T1_2mm_brain_mask_dil.nii.gz`

T1wImageBasename=`remove_ext $T1wImage`;
T1wImageBasename=`basename $T1wImage`;
T1wRestoreBasename=`remove_ext $T1wRestore`;
T1wRestoreBasename=`basename $T1wRestoreBasename`;
T1wRestoreBrainBasename=`remove_ext $T1wRestoreBrain`;
T1wRestoreBrainBasename=`basename $T1wRestoreBrainBasename`;

echo " "
echo " START: AtlasRegistration to MNI152"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/xfms/log.txt
echo "PWD = `pwd`" >> $WD/xfms/log.txt
echo "date: `date`" >> $WD/xfms/log.txt
echo " " >> $WD/xfms/log.txt

########################################## DO WORK ########################################## 

echo " ANTs T1wRestoreBrain to standard template"
# Register Input (T1w) to reference brain using ANTs
echo " "
echo ${ANTSPATH}${ANTSPATH:+/}antsRegistrationSyN.sh -d 3 -f ${ReferenceBrain} -m ${T1wRestoreBrain} -o ${WD}/xfms/${T1wRestoreBrainBasename}_to_MNI_
${ANTSPATH}${ANTSPATH:+/}antsRegistrationSyN.sh -d 3 -f ${ReferenceBrain} -m ${T1wRestoreBrain} -o ${WD}/xfms/${T1wRestoreBrainBasename}_to_MNI_

echo " antsApplyTransform"
echo " "
# combine all the affine and non-linear warps in the order: W1, A1
${ANTSPATH}${ANTSPATH:+/}antsApplyTransforms -d 3 -i ${T1wRestore} -r ${Reference} -t ${WD}/xfms/${T1wRestoreBrainBasename}_to_MNI_1Warp.nii.gz -t ${WD}/xfms/${T1wRestoreBrainBasename}_to_MNI_0GenericAffine.mat -o [${WD}/xfms/ANTs_CombinedWarp.nii.gz,1] 

# combine inverse warps in the order A1, W1
${ANTSPATH}${ANTSPATH:+/}antsApplyTransforms -d 3 -i ${T1wImage} -r ${Reference} -t [${WD}/xfms/${T1wRestoreBrainBasename}_to_MNI_0GenericAffine.mat,1] -t ${WD}/xfms/${T1wRestoreBrainBasename}_to_MNI_1InverseWarp.nii.gz -o [${WD}/xfms/ANTs_CombinedInvWarp.nii.gz,1] 

#Conversion of ANTs to FSL format
echo " ANTs to FSL warp conversion"
echo " "

# split 3 component vectors
${C3DPATH}${C3DPATH:+/}c4d -mcs ${WD}/xfms/ANTs_CombinedWarp.nii.gz -oo ${WD}/xfms/e1.nii.gz ${WD}/xfms/e2.nii.gz ${WD}/xfms/e3.nii.gz
# split 3 component vectors for Inverse Warps
${C3DPATH}${C3DPATH:+/}c4d -mcs ${WD}/xfms/ANTs_CombinedInvWarp.nii.gz -oo ${WD}/xfms/e1inv.nii.gz ${WD}/xfms/e2inv.nii.gz ${WD}/xfms/e3inv.nii.gz

# reverse y_hat
${FSLDIR}${FSLDIR:+/}bin/fslmaths ${WD}/xfms/e2.nii.gz -mul -1 ${WD}/xfms/e-2.nii.gz
# reverse y_hat for Inverse
${FSLDIR}${FSLDIR:+/}bin/fslmaths ${WD}/xfms/e2inv.nii.gz -mul -1 ${WD}/xfms/e-2inv.nii.gz

# merge to get FSL format warps
# later on clean up the eX.nii.gz
${FSLDIR}${FSLDIR:+/}bin/fslmerge -t ${OutputTransform} ${WD}/xfms/e1.nii.gz ${WD}/xfms/e-2.nii.gz ${WD}/xfms/e3.nii.gz
# merge to get FSL format Inverse warps
${FSLDIR}${FSLDIR:+/}bin/fslmerge -t ${OutputInvTransform} ${WD}/xfms/e1inv.nii.gz ${WD}/xfms/e-2inv.nii.gz ${WD}/xfms/e3inv.nii.gz

# Combine the inverse warps and get it in FSL format
# create Jacobian determinant
${ANTSPATH}${ANTSPATH:+/}CreateJacobianDeterminantImage 3 ${OutputTransform} ${WD}/xfms/NonlinearRegJacobians.nii.gz [doLogJacobian=0] [useGeometric=0]

echo "apply warp "
echo " "
# T1w set of warped outputs (brain/whole-head + restored/orig)
${FSLDIR}${FSLDIR:+/}bin/applywarp --rel --interp=spline -i ${T1wImage} -r ${Reference} -w ${OutputTransform} -o ${OutputT1wImage}
${FSLDIR}${FSLDIR:+/}bin/applywarp --rel --interp=spline -i ${T1wRestore} -r ${Reference} -w ${OutputTransform} -o ${OutputT1wImageRestore}
${FSLDIR}${FSLDIR:+/}bin/applywarp --rel --interp=nn -i ${T1wRestoreBrain} -r ${Reference} -w ${OutputTransform} -o ${OutputT1wImageRestoreBrain}
${FSLDIR}${FSLDIR:+/}bin/fslmaths ${OutputT1wImageRestore} -mas ${OutputT1wImageRestoreBrain} ${OutputT1wImageRestoreBrain}

if $useT2; then
# T2w set of warped outputs (brain/whole-head + restored/orig)
${FSLDIR}${FSLDIR:+/}bin/applywarp --rel --interp=spline -i ${T2wImage} -r ${Reference} -w ${OutputTransform} -o ${OutputT2wImage}
${FSLDIR}${FSLDIR:+/}bin/applywarp --rel --interp=spline -i ${T2wRestore} -r ${Reference} -w ${OutputTransform} -o ${OutputT2wImageRestore}
${FSLDIR}${FSLDIR:+/}bin/applywarp --rel --interp=nn -i ${T2wRestoreBrain} -r ${Reference} -w ${OutputTransform} -o ${OutputT2wImageRestoreBrain}
${FSLDIR}${FSLDIR:+/}bin/fslmaths ${OutputT2wImageRestore} -mas ${OutputT2wImageRestoreBrain} ${OutputT2wImageRestoreBrain}
fi

echo " "
echo " END: AtlasRegistration to MNI152"
echo " END: `date`" >> $WD/xfms/log.txt

########################################## QA STUFF ########################################## 

if [ -e $WD/xfms/qa.txt ] ; then rm -f $WD/xfms/qa.txt ; fi
echo "cd `pwd`" >> $WD/xfms/qa.txt
echo "# Check quality of alignment with MNI image" >> $WD/xfms/qa.txt
echo "fslview ${Reference} ${OutputT1wImageRestore}" >> $WD/xfms/qa.txt
if $useT2; then echo "fslview ${Reference} ${OutputT2wImageRestore}" >> $WD/xfms/qa.txt; fi

##############################################################################################

