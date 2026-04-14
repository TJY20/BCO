function gui()
    % 创建GUI窗口
    fig = uifigure('Name', '基于BCO贝塞尔曲线优化算法的图像细节增强', ...
                   'Position', [100 100 1000 600]);

    %==================== 按钮区域 ====================%
    btnLoad = uibutton(fig, 'push', ...
        'Text', '载入单张图像', ...
        'Position', [30 550 120 30], ...
        'ButtonPushedFcn', @(btn,event) loadSingleImage());

    btnLoadDataset = uibutton(fig, 'push', ...
        'Text', '载入数据集', ...
        'Position', [160 550 120 30], ...
        'ButtonPushedFcn', @(btn,event) loadDataset());

    btnBatchProcess = uibutton(fig, 'push', ...
        'Text', '批量增强处理', ...
        'Position', [290 550 120 30], ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(btn,event) batchProcess());

    btnSave = uibutton(fig, 'push', ...
        'Text', '保存增强图像', ...
        'Position', [420 550 120 30], ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(btn,event) saveEnhancedImage());

    %==================== 图像显示区 ====================%
    axOriginal = uiimage(fig, 'Position', [30 200 450 320], 'ScaleMethod', 'fit');
    uilabel(fig, 'Text', '原始图像', 'Position', [200 170 100 20], 'HorizontalAlignment', 'center');

    axEnhanced = uiimage(fig, 'Position', [520 200 450 320], 'ScaleMethod', 'fit');
    uilabel(fig, 'Text', 'BCO增强图像', 'Position', [690 170 100 20], 'HorizontalAlignment', 'center');

    %==================== 信息显示区 ====================%
    lblPSNR = uilabel(fig, 'Text', 'PSNR: --', ...
        'Position', [520 150 300 20], 'FontWeight', 'bold');

    lblSSIM = uilabel(fig, 'Text', 'SSIM: --', ...
        'Position', [520 120 300 20], 'FontWeight', 'bold');

    lblDatasetInfo = uilabel(fig, ...
        'Text', '数据集: 未加载', ...
        'Position', [30 150 450 20], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.8 0.2 0.2]);

    lblBatchResults = uilabel(fig, ...
        'Text', '批量处理结果: 未开始', ...
        'Position', [30 120 500 20], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.2 0.6 0.2]);

    lblAlgorithm = uilabel(fig, ...
        'Text', '算法: BCO贝塞尔曲线优化算法优化器', ...
        'Position', [30 80 280 20], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.2 0.4 0.8]);

    uilabel(fig, ...
        'Text', 'Copyright@中国矿业大学智能检测与模式识别研究所', ...
        'FontSize', 10, ...
        'Position', [700 570 280 20], ...
        'HorizontalAlignment', 'right', ...
        'FontAngle', 'italic');

    %==================== 变量初始化 ====================%
    originalImage = [];
    enhancedImage = [];
    datasetPath = '';
    imageFiles = [];
    batchResults = [];
    isDatasetLoaded = false;

    %==================================================%
    % 单张图像加载
    %==================================================%
    function loadSingleImage()
        [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', '图像文件'});
        if isequal(file, 0)
            return;
        end

        imgPath = fullfile(path, file);
        originalImage = imread(imgPath);

        rgbImage = toRGB(originalImage);
        axOriginal.ImageSource = rgbImage;

        % 重置数据集状态
        isDatasetLoaded = false;
        lblDatasetInfo.Text = '数据集: 未加载';
        lblBatchResults.Text = '批量处理结果: 未开始';

        d = uiprogressdlg(fig, ...
            'Title', 'BCO算法处理', ...
            'Message', '正在进行图像增强...', ...
            'ShowPercentage', 'on');

        d.Value = 0.25;
        enhancedImage = bco_enhance_process(rgbImage);

        d.Value = 0.8;
        axEnhanced.ImageSource = enhancedImage;

     
        psnrVal = psnr(enhancedImage, rgbImage);
        ssimVal = ssim(enhancedImage, rgbImage);

        lblPSNR.Text = sprintf('PSNR: %.2f dB', psnrVal);
        lblSSIM.Text = sprintf('SSIM: %.4f', ssimVal);

        btnSave.Enable = 'on';

        d.Value = 1.0;
        d.Message = '处理完成';
        pause(0.3);
        close(d);
    end

    %==================================================%
    % 数据集加载
    %==================================================%
    function loadDataset()
        try
            datasetPath = uigetdir('', '选择数据集文件夹');
            if isequal(datasetPath, 0)
                return;
            end

            supportedFormats = {'*.jpg', '*.jpeg', '*.png', '*.bmp', '*.tif', '*.tiff'};
            imageFiles = [];

            for i = 1:length(supportedFormats)
                files = dir(fullfile(datasetPath, supportedFormats{i}));
                if ~isempty(files)
                    imageFiles = [imageFiles; files];
                end
            end

            if isempty(imageFiles)
                uialert(fig, '在选择的文件夹中未找到支持的图像文件。', '提示');
                return;
            end

            isDatasetLoaded = true;
            lblDatasetInfo.Text = sprintf('数据集: %s (%d 张图像)', datasetPath, length(imageFiles));
            btnBatchProcess.Enable = 'on';

            % 显示第一张图像预览
            previewImagePath = fullfile(datasetPath, imageFiles(1).name);
            originalImage = imread(previewImagePath);
            axOriginal.ImageSource = toRGB(originalImage);

            axEnhanced.ImageSource = [];
            lblPSNR.Text = 'PSNR: --';
            lblSSIM.Text = 'SSIM: --';

            uialert(fig, sprintf('成功加载数据集！\n共找到 %d 张图像。', length(imageFiles)), '数据集加载完成');

        catch ME
            uialert(fig, sprintf('加载数据集时出错: %s', ME.message), '错误');
        end
    end

    %==================================================%
    % 批量处理
    %==================================================%
    function batchProcess()
        if ~isDatasetLoaded || isempty(imageFiles)
            uialert(fig, '请先载入数据集。', '提示');
            return;
        end

        try
            outputFolder = fullfile(datasetPath, '增强图像');
            if ~exist(outputFolder, 'dir')
                mkdir(outputFolder);
            end

            totalPSNR = 0;
            totalSSIM = 0;
            processedCount = 0;
            failList = {};

            batchResults = struct();
            batchResults.imageCount = length(imageFiles);
            batchResults.startTime = datetime('now');
            batchResults.details = struct([]);

            d = uiprogressdlg(fig, ...
                'Title', '批量处理进度', ...
                'Message', '正在初始化批量处理...', ...
                'ShowPercentage', 'on');

            for i = 1:length(imageFiles)
                d.Message = sprintf('正在处理第 %d/%d 张图像: %s', i, length(imageFiles), imageFiles(i).name);
                d.Value = i / length(imageFiles);

                try
                    imgPath = fullfile(datasetPath, imageFiles(i).name);
                    originalImg = imread(imgPath);
                    rgbImg = toRGB(originalImg);

                    enhancedImg = bco_enhance_process(rgbImg);

                    psnrVal = psnr(enhancedImg, rgbImg);
                    ssimVal = ssim(enhancedImg, rgbImg);

                    totalPSNR = totalPSNR + psnrVal;
                    totalSSIM = totalSSIM + ssimVal;
                    processedCount = processedCount + 1;

                    detail = struct();
                    detail.filename = imageFiles(i).name;
                    detail.psnr = psnrVal;
                    detail.ssim = ssimVal;
                    detail.processTime = datetime('now');

                    if isempty(batchResults.details)
                        batchResults.details = detail;
                    else
                        batchResults.details(end+1) = detail; 
                    end

                    [~, name, ext] = fileparts(imageFiles(i).name);
                    outputFilename = [name '_enhanced' ext];
                    outputPath = fullfile(outputFolder, outputFilename);
                    imwrite(enhancedImg, outputPath);

                    % 最后一张用于预览
                    if i == length(imageFiles)
                        axOriginal.ImageSource = rgbImg;
                        axEnhanced.ImageSource = enhancedImg;
                        lblPSNR.Text = sprintf('PSNR: %.2f dB', psnrVal);
                        lblSSIM.Text = sprintf('SSIM: %.4f', ssimVal);
                    end

                catch ME
                    failList{end+1} = sprintf('%s -> %s', imageFiles(i).name, ME.message); %#ok<AGROW>
                    continue;
                end
            end

            if processedCount > 0
                avgPSNR = totalPSNR / processedCount;
                avgSSIM = totalSSIM / processedCount;
            else
                avgPSNR = 0;
                avgSSIM = 0;
            end

            batchResults.avgPSNR = avgPSNR;
            batchResults.avgSSIM = avgSSIM;
            batchResults.endTime = datetime('now');
            batchResults.totalTime = batchResults.endTime - batchResults.startTime;
            batchResults.processedCount = processedCount;
            batchResults.failList = failList;

            generateBatchReport(outputFolder, batchResults);

            lblBatchResults.Text = sprintf('批量处理完成! 平均PSNR: %.2f dB, 平均SSIM: %.4f', avgPSNR, avgSSIM);

            close(d);

            uialert(fig, sprintf(['批量处理完成！\n' ...
                                  '成功处理 %d/%d 张图像\n' ...
                                  '平均PSNR: %.2f dB\n' ...
                                  '平均SSIM: %.4f\n' ...
                                  '结果保存在: %s'], ...
                                  processedCount, length(imageFiles), avgPSNR, avgSSIM, outputFolder), ...
                                  '批量处理完成');

        catch ME
            if exist('d', 'var') && isvalid(d)
                close(d);
            end
            uialert(fig, sprintf('批量处理过程中出错: %s', ME.message), '错误');
        end
    end

    %==================================================%
    % 报告生成
    %==================================================%
    function generateBatchReport(outputFolder, results)
        reportPath = fullfile(outputFolder, '处理报告.txt');
        fid = fopen(reportPath, 'w', 'n', 'UTF-8');

        if fid == -1
            uialert(fig, '无法创建处理报告文件。', '错误');
            return;
        end

        try
            fprintf(fid, 'BCO图像增强批量处理报告\n');
            fprintf(fid, '==========================\n\n');
            fprintf(fid, '处理时间: %s\n', char(results.startTime));
            fprintf(fid, '完成时间: %s\n', char(results.endTime));
            fprintf(fid, '总处理时间: %s\n\n', char(results.totalTime));

            fprintf(fid, '总图像数量: %d\n', results.imageCount);
            fprintf(fid, '成功处理: %d\n', results.processedCount);
            fprintf(fid, '处理失败: %d\n\n', results.imageCount - results.processedCount);

            fprintf(fid, '总体指标（相对原图）:\n');
            fprintf(fid, '平均PSNR: %.2f dB\n', results.avgPSNR);
            fprintf(fid, '平均SSIM: %.4f\n\n', results.avgSSIM);

            fprintf(fid, '详细处理结果:\n');
            fprintf(fid, '%-35s %-14s %-14s %-22s\n', '文件名', 'PSNR(dB)', 'SSIM', '处理时间');
            fprintf(fid, '%s\n', repmat('-', 1, 95));

            for i = 1:length(results.details)
                detail = results.details(i);
                fprintf(fid, '%-35s %-14.2f %-14.4f %-22s\n', ...
                    detail.filename, detail.psnr, detail.ssim, char(detail.processTime));
            end

            if ~isempty(results.failList)
                fprintf(fid, '\n失败记录:\n');
                fprintf(fid, '%s\n', repmat('-', 1, 50));
                for i = 1:length(results.failList)
                    fprintf(fid, '%s\n', results.failList{i});
                end
            end

            fclose(fid);

        catch ME
            fclose(fid);
            uialert(fig, sprintf('生成报告时出错: %s', ME.message), '错误');
        end
    end

    %==================================================%
    % 保存增强图像
    %==================================================%
    function saveEnhancedImage()
        if isempty(enhancedImage)
            uialert(fig, '请先载入图像并处理。', '提示');
            return;
        end

        [file, path] = uiputfile({'*.png', 'PNG图像'; '*.jpg', 'JPG图像'}, '保存增强图像');
        if isequal(file, 0)
            return;
        end

        imwrite(enhancedImage, fullfile(path, file));
        uialert(fig, '图像保存成功！', '成功');
    end

    %==================================================%
    % BCO增强处理：只增强亮度通道
    %==================================================%
 function out = bco_enhance_process(in)
    factor = 2;   

    % 如果是灰度图，直接处理
    if size(in, 3) == 1
        Y = double(in);
        H = BCO(Y);
        H = imresize(H, [size(Y,1), size(Y,2)], 'bilinear');

        Y_enhanced = Y + factor * H;
        Y_enhanced = max(min(Y_enhanced, 255), 0);

        out = uint8(Y_enhanced);
        return;
    end

    % 彩色图：转 YCbCr，只增强亮度通道
    ycbcrImg = rgb2ycbcr(in);

    Y  = double(ycbcrImg(:,:,1));
    Cb = ycbcrImg(:,:,2);
    Cr = ycbcrImg(:,:,3);

    % 亮度细节提取
    H = BCO(Y);
    H = imresize(H, [size(Y,1), size(Y,2)], 'bilinear');

    % 增强叠加
    Y_enhanced = Y + factor * H;
    Y_enhanced = max(min(Y_enhanced, 255), 0);

    % 合并回去
    ycbcrImg(:,:,1) = uint8(Y_enhanced);
    ycbcrImg(:,:,2) = Cb;
    ycbcrImg(:,:,3) = Cr;

    out = ycbcr2rgb(ycbcrImg);
 end
end