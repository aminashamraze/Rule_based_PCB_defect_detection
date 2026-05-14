# Rule_based_PCB_defect_detection
This is my  MATLAB image-processing project for detecting PCB open and short defects by comparing a reference PCB image with a test PCB image. The pipeline uses image alignment, binary differencing, morphological filtering, area-based noise removal, and polarity/connectivity-based classification.

This project is a MATLAB-based PCB defect detection pipeline that identifies open-circuit and short-circuit defects by comparing a reference PCB image with a test PCB image.

Unlike many PCB inspection projects that rely on machine learning, this project uses classical rule-based image processing techniques. The goal is to build an interpretable and debuggable system where each processing step has a clear purpose.

## Project Overview

Printed Circuit Boards (PCBs) can contain manufacturing defects such as broken traces, missing copper, unwanted copper bridges, and short circuits. Detecting these defects visually can be difficult, especially when the defects are small or when the board images contain noise, slight misalignment, or thin traces.

This project compares a defect-free reference PCB image against a test PCB image and detects regions where the two images differ. The detected regions are then classified as:

- **Open circuit**
- **Short circuit**
- **Unsure**

The pipeline is designed to be transparent, modular, and easy to debug.

## Key Features
This program was written in matlab.
- Reference and test image comparison
- Image alignment using translation search
- Binary image processing
- Defect mask generation
- Morphological filtering
- Connected component analysis
- Region-based defect classification
- Open-circuit and short-circuit labeling
- Visualization of detected defects

## Defect Classes

The detected regions are classified using color-coded bounding boxes:

| Color | Defect Type |
|---|---|
| Blue | Open circuit |
| Red | Short circuit |
| Yellow | Unsure |

## Binary Image Convention

In this project, the PCB images follow the binary convention:
Copper     = 0
Background = 1
## Methodology
The project follows a rule-based image processing pipeline.

1. Image Preprocessing

The reference and test images are converted into binary images. This simplifies the comparison by reducing the images to copper and background regions.

2. Image Alignment

Small shifts between the reference image and the test image can create false defect regions. To reduce this problem, the project performs a brute-force translation search over a small range of horizontal and vertical shifts.

The best alignment is selected by minimizing the pixel-wise difference between the reference and shifted test image.

Conceptually:

best shift = argmin XOR(reference image, shifted test image)

This helps ensure that detected differences are more likely to be real defects rather than alignment errors.

3. Defect Mask Generation

After alignment, the project compares the reference image and test image to generate two main defect masks:

missingMask = refWork & ~testWork;
extraMask   = testWork & ~refWork;

These masks help separate two types of differences:

Missing copper, which may indicate an open circuit
Extra copper, which may indicate a short circuit
4. Morphological Filtering

Morphological operations are used to clean up noise and improve defect region quality.

The project uses operations such as:
bwareaopen
imopen
imclose
Structuring elements such as strel('disk', radius)

These operations help remove small noise, smooth regions, and connect fragmented defect areas.

5. Connected Component Analysis

After filtering, connected components are extracted from the defect mask. Each connected region is treated as a candidate defect.

For each region, properties such as area, bounding box, centroid, major axis length, and minor axis length are computed using regionprops.

6. Region Classification

Each detected region is classified using local polarity and connectivity logic.

Polarity helps determine whether the region mostly comes from the missing-copper mask or the extra-copper mask. Connectivity helps determine whether the defect disrupts an existing copper path or creates an unintended connection between copper regions.

This is useful because raw pixel differences alone are not enough. A noisy region or edge artifact may look like a defect, but local context helps decide whether it is likely to be an open circuit, short circuit, or uncertain case.

## Results
Currently, the pipeline was tested for 20 image sets and it recognized all of the defects and labeled them correctly. 
<img width="1142" height="367" alt="Results_18" src="https://github.com/user-attachments/assets/c56d251f-41de-45c8-9648-30adfc0aa3b3" />

## Tools Used
1. Matlab
2. Image Processing toolbox
Important matlab functions used:
imbinarize
imtranslate
xor
bwareaopen
imopen
imclose
strel
bwconncomp
regionprops
imshow
rectangle

## How to Run?
Copy images [ both temp and ref] in the project folder in the matlab. Then, use console to call the function script, using example command;
>> processPair(fullfile(pwd, 'images', '92000001_temp.jpg'), fullfile(pwd, 'images', '92000001_test.jpg'),1)
Replace images with the folder name that contains images.

The complete dataset was taken from https://github.com/tangsanli5201/DeepPCB.
