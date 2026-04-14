function out = grad(I)
    % 转换为灰度图像
    if size(I, 3) == 3
        I = rgb2gray(I);
    end

    % 转换为 double 类型
    I = double(I);

    % 轻微平滑，降低噪声梯度
    I = imgaussfilt(I, 0.5);

    [Gx, Gy] = imgradientxy(I, 'sobel');

    % 梯度幅值
    out = sqrt(Gx.^2 + Gy.^2);
end