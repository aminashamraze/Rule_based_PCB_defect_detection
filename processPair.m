function result = processPair(refFile, testFile, showFigure)
% processPair
% Processes one PCB reference/test image pair and returns detection results.
%
% Inputs:
%   refFile    - path to reference/template image
%   testFile   - path to test/defect image
%   showFigure - true/false, whether to display annotated figure
% It is recommended to make a new folder, call it PCB_Defect_Project,
% inside this folder keep this processPair.m script and make another folder
%named Images. Copy all images (test, and temp there). 
% In console, type following command, to observe the resulting image. 
% >> processPair(fullfile(pwd, 'images', '92000011_temp.jpg'), fullfile(pwd, 'images', '92000011_test.jpg'),1)

% Output:
%   result - structure containing images, masks, labels, counts, and shifts

    if nargin < 3
        showFigure = false;
    end

    % =========================================================
    % STEP 1: READ IMAGES
    % =========================================================
    refImg = imread(refFile);
    testImg = imread(testFile);

    % Convert to grayscale if needed
    if ndims(refImg) == 3
        refImg = rgb2gray(refImg);
    end

    if ndims(testImg) == 3
        testImg = rgb2gray(testImg);
    end

    % Convert to binary
    refBin = imbinarize(refImg);
    testBin = imbinarize(testImg);

    % IMPORTANT:
    % For many PCB datasets, copper traces appear dark.
    % If copper is dark in your dataset, uncomment these lines:
    %
    % refBin = ~refBin;
    % testBin = ~testBin;

    % Resize if dimensions differ
    if ~isequal(size(refBin), size(testBin))
        testBin = imresize(testBin, size(refBin));
    end

    % =========================================================
    % STEP 2: ALIGN TEST IMAGE TO REFERENCE
    % =========================================================
    bestScore = inf;
    bestDx = 0;
    bestDy = 0;
    bestAligned = testBin;

    for dx = -5:5
        for dy = -5:5
            shifted = imtranslate(testBin, [dx, dy], 'FillValues', 0);
            score = sum(xor(refBin, shifted), 'all');

            if score < bestScore
                bestScore = score;
                bestDx = dx;
                bestDy = dy;
                bestAligned = shifted;
            end
        end
    end

    testAligned = bestAligned;

    % =========================================================
    % STEP 3: WORKING COPIES
    % =========================================================
    refWork  = refBin;
    testWork = testAligned;

% Binary convention:
%   copper     = 0
%   background = 1
% since background is white in which copper is shown black in original
% dataset
% Missing copper/open:
%   reference has copper, test has background
%
% Extra copper/short:
%   reference has background, test has copper
% =========================================================

missingMask = (~refWork) & testWork;    % copper missing from test
extraMask   = refWork & (~testWork);    % extra copper added in test
defectMask  = xor(refWork, testWork);
    % =========================================================
    % STEP 5: REMOVE THIN EDGE ARTIFACTS
    % =========================================================
    minAreaInitial = 15;

    defectMask  = bwareaopen(defectMask, minAreaInitial);
    missingMask = bwareaopen(missingMask, minAreaInitial);
    extraMask   = bwareaopen(extraMask, minAreaInitial);

    seOpen = strel('disk', 2);

    defectMask = imopen(defectMask, seOpen);
    extraMask  = imopen(extraMask, seOpen);

    % Keep missingMask less aggressively processed
    missingMask = bwareaopen(missingMask, 5);

    seClose = strel('disk', 2);

    defectMask  = imclose(defectMask, seClose);
    missingMask = imclose(missingMask, seClose);
    extraMask   = imclose(extraMask, seClose);

    % =========================================================
    % STEP 6: FILTER REGIONS BY AREA AND THICKNESS
    % =========================================================
    cc = bwconncomp(defectMask);

    stats = regionprops(cc, ...
        'Area', ...
        'BoundingBox', ...
        'MajorAxisLength', ...
        'MinorAxisLength', ...
        'Centroid', ...
        'PixelIdxList');

    finalMask = false(size(defectMask));

    minAreaFinal = 40;
    minThickness = 3;

    for k = 1:length(stats)
        areaVal = stats(k).Area;
        thicknessVal = stats(k).MinorAxisLength;

        if areaVal >= minAreaFinal && thicknessVal >= minThickness
            finalMask(cc.PixelIdxList{k}) = true;
        end
    end

    defectMask = finalMask;

    % Recompute connected components after final filtering
    cc = bwconncomp(defectMask);

    stats = regionprops(cc, ...
        'BoundingBox', ...
        'Area', ...
        'Centroid', ...
        'PixelIdxList');

% =========================================================
% STEP 7: CLASSIFY EACH DETECTED REGION USING POLARITY + CONNECTIVITY
%
% Blue   = open circuit
% Red    = short circuit
% Yellow = unsure
%
% Binary convention:
%   copper     = 0
%   background = 1
% =========================================================

numRegions = cc.NumObjects;

labels = strings(numRegions, 1);
boxColors = zeros(numRegions, 3);

openCount = 0;
shortCount = 0;
unsureCount = 0;

imgH = size(refWork, 1);
imgW = size(refWork, 2);

pad = 12;
polarityThreshold = 0.60;
seTouch = strel('disk', 2);

for k = 1:numRegions

    box = stats(k).BoundingBox;
    pixels = stats(k).PixelIdxList;

    missingCount = sum(missingMask(pixels));
    extraCount   = sum(extraMask(pixels));

    totalCount = missingCount + extraCount;

    if totalCount == 0
        labels(k) = "UNSURE";
        boxColors(k,:) = [1 1 0];
        unsureCount = unsureCount + 1;
        continue;
    end

    missingRatio = missingCount / totalCount;
    extraRatio   = extraCount / totalCount;

    % Expanded local ROI around the defect
    x1 = max(floor(box(1)) - pad, 1);
    y1 = max(floor(box(2)) - pad, 1);
    x2 = min(ceil(box(1) + box(3)) + pad, imgW);
    y2 = min(ceil(box(2) + box(4)) + pad, imgH);

    refROI  = refWork(y1:y2, x1:x2);
    testROI = testWork(y1:y2, x1:x2);

    missingROI = missingMask(y1:y2, x1:x2);
    extraROI   = extraMask(y1:y2, x1:x2);

    % Convert to copper masks
    % copper pixels become logical 1
    refCopperROI  = ~refROI;
    testCopperROI = ~testROI;

    % Clean tiny noise
    refCopperROI  = bwareaopen(refCopperROI, 10);
    testCopperROI = bwareaopen(testCopperROI, 10);

    % Component labels
    refCC = bwconncomp(refCopperROI);
    testCC = bwconncomp(testCopperROI);

    refLabel = labelmatrix(refCC);
    testLabel = labelmatrix(testCC);

    % Dilated defect area slightly so it can touch nearby trace fragments
    missingTouch = imdilate(missingROI, seTouch);
    extraTouch   = imdilate(extraROI, seTouch);

    % =====================================================
    % OPEN TEST:
    % Missing copper should break one original trace into
    % two or more pieces in the test image.
    % =====================================================
    refLabelsNearMissing = unique(refLabel(missingTouch & refCopperROI));
    refLabelsNearMissing(refLabelsNearMissing == 0) = [];

    testLabelsNearMissing = unique(testLabel(missingTouch & testCopperROI));
    testLabelsNearMissing(testLabelsNearMissing == 0) = [];

    isTrueOpen = ...
        missingRatio >= polarityThreshold && ...
        numel(refLabelsNearMissing) == 1 && ...
        numel(testLabelsNearMissing) >= 2;

    % =====================================================
    % SHORT TEST:
    % Extra copper should connect two or more traces that
    % were separate in the reference image.
    % =====================================================
    refLabelsNearExtra = unique(refLabel(extraTouch & refCopperROI));
    refLabelsNearExtra(refLabelsNearExtra == 0) = [];

    testLabelsNearExtra = unique(testLabel(extraTouch & testCopperROI));
    testLabelsNearExtra(testLabelsNearExtra == 0) = [];

    isTrueShort = ...
        extraRatio >= polarityThreshold && ...
        numel(refLabelsNearExtra) >= 2 && ...
        numel(testLabelsNearExtra) == 1;

    % Final classification
    if isTrueOpen
        labels(k) = "OPEN";
        boxColors(k,:) = [0 0 1];     % blue
        openCount = openCount + 1;

    elseif isTrueShort
        labels(k) = "SHORT";
        boxColors(k,:) = [1 0 0];     % red
        shortCount = shortCount + 1;

    else
        labels(k) = "UNSURE";
        boxColors(k,:) = [1 1 0];     % yellow
        unsureCount = unsureCount + 1;
    end
end
% =========================================================
% STEP 8: REFERENCE, TEST, AND FINAL RESULT ONLY
% =========================================================
if showFigure
    figure('Units', 'normalized', 'OuterPosition', [0 0 1 1]);

    t = tiledlayout(1, 3, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    % -----------------------------
    % Reference image
    % -----------------------------
    nexttile;
    imshow(refBin);
    title('Reference', 'FontSize', 10);

    % -----------------------------
    % Aligned test image
    % -----------------------------
    nexttile;
    imshow(testAligned);
    title('Test', 'FontSize', 10);

    % -----------------------------
    % Final detected image
    % -----------------------------
    nexttile;
    imshow(testAligned);
    title('Detected Defects', 'FontSize', 10);
    hold on;

    for k = 1:length(stats)
        box = stats(k).BoundingBox;
        colorNow = boxColors(k,:);

        rectangle('Position', box, ...
                  'EdgeColor', colorNow, ...
                  'LineWidth', 1.5);

        text(box(1), max(box(2) - 2, 1), labels(k), ...
             'Color', colorNow, ...
             'FontSize', 8, ...
             'FontWeight', 'normal');
    end

    hold off;
end

    % =========================================================
    % STEP 9: STORE OUTPUT RESULT
    % =========================================================
    result.refBin = refBin;
    result.testBin = testBin;
    result.testAligned = testAligned;

    result.missingMask = missingMask;
    result.extraMask = extraMask;
    result.defectMask = defectMask;

    result.stats = stats;
    result.labels = labels;
    result.boxColors = boxColors;

    result.openCount = openCount;
    result.shortCount = shortCount;
    result.unsureCount = unsureCount;
    result.numRegions = numRegions;

    result.bestDx = bestDx;
    result.bestDy = bestDy;
    result.bestScore = bestScore;
end