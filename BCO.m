function Residual = BCO(image)

    %------------------------- 参数设置 -------------------------%
    hfs_y1 = 20;          % padding 边界厚度
    patch_radius = 2;     % patch 半径 = 2，对应 patch 大小为 5x5
    step_size = 1;        % 在 L1 上滑动采样步长

    %------------------------- 数据准备 -------------------------%
    if ndims(image) == 3
        image = rgb2gray(image);
    end
    I0 = double(image);

    %------------------------- 多尺度分解 -------------------------%
    
    L1 = imresize(I0, 1.25, 'bilinear');

    % L2：再缩回原尺寸
    L2 = imresize(L1, size(I0), 'bilinear');

    % H0：原图与低频近似层之差
    H0 = I0 - L2;

    %------------------------- 边界填充 -------------------------%
    largeL1 = padarray(L1, [hfs_y1, hfs_y1], 'replicate');
    largeL2 = padarray(L2, [hfs_y1, hfs_y1], 'replicate');
    largeH0 = padarray(H0, [hfs_y1, hfs_y1], 'replicate');

    %------------------------- 特征提取 -------------------------%
    grad_largeL1 = grad(largeL1);
    grad_largeL2 = grad(largeL2);

    texture_largeL1 = texture(largeL1);
    texture_largeL2 = texture(largeL2);

    %------------------------- 初始化累计图 -------------------------%
    sumh0 = zeros(size(largeL1));
    counth0 = zeros(size(largeL1));

    [newh1, neww1] = size(L1);
    [imgH, imgW] = size(I0);
    [rowsL2, colsL2] = size(L2);

    coef_x = imgH / newh1;
    coef_y = imgW / neww1;

    %======================================================================
    % 在 L1 上逐 patch 遍历
    %======================================================================
    for centerx = 1:step_size:newh1
        for centery = 1:step_size:neww1

            %--------------------------------------------------------------
            % 1) 在 largeL1 中提取当前参考 patch
            %--------------------------------------------------------------
            p_L1 = largeL1(hfs_y1 + centerx - patch_radius : hfs_y1 + centerx + patch_radius, ...
                           hfs_y1 + centery - patch_radius : hfs_y1 + centery + patch_radius);

            p_grad_L1 = grad_largeL1(hfs_y1 + centerx - patch_radius : hfs_y1 + centerx + patch_radius, ...
                                     hfs_y1 + centery - patch_radius : hfs_y1 + centery + patch_radius);

            p_texture_L1 = texture_largeL1(hfs_y1 + centerx - patch_radius : hfs_y1 + centerx + patch_radius, ...
                                           hfs_y1 + centery - patch_radius : hfs_y1 + centery + patch_radius);

            %--------------------------------------------------------------
            % 2) 将 L1 当前中心点映射到 L2 坐标系
            %--------------------------------------------------------------
            newx = round(centerx * coef_x);
            newy = round(centery * coef_y);

            %--------------------------------------------------------------
            % 3) 构造局部搜索窗口 [LB, UB]
            
            %--------------------------------------------------------------
            LB = [max(1 + patch_radius, newx - 5), ...
                  max(1 + patch_radius, newy - 5)];

            UB = [min(rowsL2 - patch_radius, newx + 5), ...
                  min(colsL2 - patch_radius, newy + 5)];

            %--------------------------------------------------------------
            % 4) 调用 BCO 局部优化器
            %--------------------------------------------------------------
            if any(LB > UB)
                Best_Pos = [min(max(newx, 1 + patch_radius), rowsL2 - patch_radius), ...
                            min(max(newy, 1 + patch_radius), colsL2 - patch_radius)];
            else
                Best_Pos = BCO_patch_optimizer(largeL2, grad_largeL2, texture_largeL2, ...
                                               p_L1, p_grad_L1, p_texture_L1, ...
                                               hfs_y1, LB, UB);
            end

            retrievex = round(Best_Pos(1));
            retrievey = round(Best_Pos(2));

            %--------------------------------------------------------------
            % 5) 从高频层 largeH0 中提取对应位置的高频块
            %--------------------------------------------------------------
            q_p_H0 = double(largeH0(hfs_y1 + retrievex - patch_radius : hfs_y1 + retrievex + patch_radius, ...
                                    hfs_y1 + retrievey - patch_radius : hfs_y1 + retrievey + patch_radius));

            %--------------------------------------------------------------
            % 6) 累计回当前参考位置
            %--------------------------------------------------------------
            sumh0(hfs_y1 + centerx - patch_radius : hfs_y1 + centerx + patch_radius, ...
                  hfs_y1 + centery - patch_radius : hfs_y1 + centery + patch_radius) = ...
            sumh0(hfs_y1 + centerx - patch_radius : hfs_y1 + centerx + patch_radius, ...
                  hfs_y1 + centery - patch_radius : hfs_y1 + centery + patch_radius) + q_p_H0;

            counth0(hfs_y1 + centerx - patch_radius : hfs_y1 + centerx + patch_radius, ...
                    hfs_y1 + centery - patch_radius : hfs_y1 + centery + patch_radius) = ...
            counth0(hfs_y1 + centerx - patch_radius : hfs_y1 + centerx + patch_radius, ...
                    hfs_y1 + centery - patch_radius : hfs_y1 + centery + patch_radius) + 1;
        end
    end

    %------------------------- 重叠平均 -------------------------%
    counth0(counth0 < 1) = 1;
    averageh0 = sumh0 ./ counth0;

    % 去掉 padding
    Residual = averageh0(hfs_y1 + 1:end - hfs_y1, hfs_y1 + 1:end - hfs_y1);
end


%% =========================================================================
%  BCO 局部 patch 匹配优化器
% =========================================================================
function BestPos = BCO_patch_optimizer(largeL2, grad_largeL2, texture_largeL2, ...
                                       p_L1, p_grad_L1, p_texture_L1, ...
                                       hfs_y1, LB, UB)

    Dim = 2;

    % 参数保持不大改
    PopSize = 4;
    MaxIt   = 6;

    %------------------------- 初始化种群 -------------------------%
    PopPos = initialization_bco(PopSize, Dim, UB, LB);
    PopFit = zeros(PopSize, 1);

    for i = 1:PopSize
        PopFit(i) = patch_fitness(PopPos(i,:), largeL2, grad_largeL2, texture_largeL2, ...
                                  p_L1, p_grad_L1, p_texture_L1, hfs_y1);
    end

    [BestFit, idx] = min(PopFit);
    BestPos = PopPos(idx, :);

    %======================================================================
    % 迭代优化
    %======================================================================
    for It = 1:MaxIt

        Alpha0 = 1 + 80 * It / MaxIt + 0.02 * (10 * It / MaxIt)^3;
        A0 = sin(pi/2 * (1 - It / MaxIt));

        for i = 1:PopSize

            Alpha = 1 + (2 * rand - 1) / Alpha0;
            A = (0.4 + 2 * log(1 / rand)) * A0;

            if A > 1

                %===================== 探索阶段 =====================%
                if rand > 0.5
                    j = pick_distinct_index(PopSize, i);
                    k = pick_distinct_index(PopSize, [i, j]);

                    r1 = rand;
                    if r1 < 0.8
                        P3 = mean(PopPos, 1) + 2 * randn(1, Dim) .* (PopPos(k,:) - PopPos(j,:));
                    elseif r1 > 0.9
                        rand_dim_val = PopPos(k, randi(Dim));
                        P3 = PopPos(j,:) + 2 * randn * (rand_dim_val - PopPos(j,:));
                    else
                        P3 = PopPos(j,:) + 2 * randn * (LB + rand(1, Dim) .* (UB - LB));
                    end

                    P0 = PopPos(i,:);
                    P1 = PopPos(j,:);
                    P2 = PopPos(k,:);

                    NewPos = (1 - Alpha)^3 * P0 ...
                           + 3 * (1 - Alpha)^2 * Alpha * P1 ...
                           + 3 * (1 - Alpha) * Alpha^2 * P2 ...
                           + Alpha^3 * P3;

                else
                    j = pick_distinct_index(PopSize, i);

                    P0 = PopPos(i,:);
                    P1 = PopPos(j,:);

                    if rand > 0.5
                        P2 = PopPos(i,:) + randn * (BestPos - PopPos(j,:));
                    else
                        P2 = PopPos(i,:) + randn * (mean(PopPos, 1) - PopPos(j,:));
                    end

                    NewPos = (1 - Alpha)^2 * P0 ...
                           + 2 * (1 - Alpha) * Alpha * P1 ...
                           + Alpha^2 * P2;
                end

            else

                %===================== 开发阶段 =====================%
                if rand > 0.5
                    j = pick_distinct_index(PopSize, i);

                    P0 = PopPos(i,:);
                    if rand < 0.5
                        P1 = BestPos + (PopPos(j,:) - PopPos(i,:)) / 2;
                    else
                        P1 = BestPos - (PopPos(j,:) + PopPos(i,:)) / 2;
                    end

                    NewPos = (1 - Alpha) * P0 + Alpha * P1;

                else
                    if rand > 0.5
                        P0 = PopPos(i,:);
                        if rand > 0.5
                            P1 = mean(PopPos, 1) + randn * (PopPos(i,:) - mean(PopPos, 1));
                        else
                            P1 = mean(PopPos, 1) + randn * mean(PopPos, 1);
                        end

                        NewPos = (1 - Alpha) .* P0 + Alpha .* P1;

                    else
                        P0 = PopPos(i,:);
                        P1 = PopPos(i,:);

                        for d = 1:Dim
                            if rand > 0.5
                                k = pick_distinct_index(PopSize, i);
                                P1(d) = (1 - Alpha) * PopPos(i,d) + Alpha * PopPos(k,d);
                            end
                        end

                        NewPos = (1 - Alpha) * P0 + Alpha * P1;
                    end
                end
            end

            %------------------------- 边界修复 -------------------------%
            NewPos = reflective_boundary_check(NewPos, UB, LB);

            %------------------------- 适应度计算 -------------------------%
            NewFit = patch_fitness(NewPos, largeL2, grad_largeL2, texture_largeL2, ...
                                   p_L1, p_grad_L1, p_texture_L1, hfs_y1);

            %------------------------- 贪心更新 -------------------------%
            if NewFit < PopFit(i)
                PopPos(i,:) = NewPos;
                PopFit(i)   = NewFit;

                if NewFit < BestFit
                    BestFit = NewFit;
                    BestPos = NewPos;
                end
            end
        end

        %------------------------- 精英保留 -------------------------%
        [worstFit, worstIdx] = max(PopFit);
        if BestFit < worstFit
            PopPos(worstIdx,:) = BestPos;
            PopFit(worstIdx)   = BestFit;
        end
    end
end


%% =========================================================================
%  patch 适应度函数
% =========================================================================
function fitness = patch_fitness(pos, largeL2, grad_largeL2, texture_largeL2, ...
                                 p_L1, p_grad_L1, p_texture_L1, hfs_y1)

    patch_radius = 2;

    % ===== 建议参数 =====
    wg = 0.0020;   % 梯度权重
    wt = 0.0003;   % 纹理权重
    % ===================

    x = round(pos(1));
    y = round(pos(2));

    [rows_pad, cols_pad] = size(largeL2);

    row_min = hfs_y1 + x - patch_radius;
    row_max = hfs_y1 + x + patch_radius;
    col_min = hfs_y1 + y - patch_radius;
    col_max = hfs_y1 + y + patch_radius;

    if row_min < 1 || row_max > rows_pad || col_min < 1 || col_max > cols_pad
        fitness = inf;
        return;
    end

    try
        p_L2         = double(largeL2(row_min:row_max, col_min:col_max));
        p_grad_L2    = double(grad_largeL2(row_min:row_max, col_min:col_max));
        p_texture_L2 = double(texture_largeL2(row_min:row_max, col_min:col_max));

        p_L1         = double(p_L1);
        p_grad_L1    = double(p_grad_L1);
        p_texture_L1 = double(p_texture_L1);

        % 均值差
        intensity_diff = mean(abs(p_L1(:) - p_L2(:)));
        grad_diff      = mean(abs(p_grad_L1(:) - p_grad_L2(:)));
        texture_diff   = mean(abs(p_texture_L1(:) - p_texture_L2(:)));

        fitness = intensity_diff + wg * grad_diff + wt * texture_diff;

    catch
        fitness = inf;
    end
end


%% =========================================================================
%  BCO 初始化
% =========================================================================
function X = initialization_bco(N, Dim, UB, LB)
    X = zeros(N, Dim);
    for d = 1:Dim
        X(:, d) = rand(N, 1) .* (UB(d) - LB(d)) + LB(d);
    end
end


%% =========================================================================
%  反射边界处理
% =========================================================================
function new_pos = reflective_boundary_check(pos, UB, LB)

    new_pos = pos;

    for d = 1:numel(pos)
        if new_pos(d) < LB(d)
            new_pos(d) = 2 * LB(d) - new_pos(d);
        elseif new_pos(d) > UB(d)
            new_pos(d) = 2 * UB(d) - new_pos(d);
        end
    end

    new_pos = max(new_pos, LB);
    new_pos = min(new_pos, UB);
end


%% =========================================================================
%  随机选取与 forbidden 不同的下标
% =========================================================================
function idx = pick_distinct_index(N, forbidden)

    idx = randi(N);
    while any(idx == forbidden)
        idx = randi(N);
    end
end