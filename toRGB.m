function rgb = toRGB(img)
    if size(img, 3) == 1
        rgb = repmat(img, [1 1 3]);
    else
        rgb = img;
    end
end