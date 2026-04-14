function out = texture(img)
    % 转换为灰度图像（如果是彩色图）
    if size(img, 3) == 3
        img_gray = rgb2gray(img);
    else
        img_gray = img;
    end

    % 转换为 double
    img_gray = double(img_gray);

    % 先做轻微平滑，减少噪声对纹理响应的干扰
    img_gray = imgaussfilt(img_gray, 0.6);

    % 定义拉普拉斯算子
    laplacian_kernel = [0 -1  0;
                       -1  4 -1;
                        0 -1  0];

    % 保持 double，并取绝对值
    out = abs(conv2(img_gray, laplacian_kernel, 'same'));
end