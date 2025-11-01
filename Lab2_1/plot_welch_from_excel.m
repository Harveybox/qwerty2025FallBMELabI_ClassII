function plot_welch_from_excel()
% 读取 properties_summary.xlsx，解析“材料-速度-编号”，
% 对每个指标做 Welch's t-test 并绘图（均值±SD、显著性括号、右上角说明）。
% 另外导出所有比较的 p 值和显著性结论到 CSV：
% fig_out/ttest_summary.csv
%
% 数据格式：
%   第1列：样本名（如 "iron-10-01" 或 "steel-50-03"）
%   第2~4列：三项数值指标（列名用于识别 E、sigma_s、sigma_UTS 等）

fname = 'properties_summary.xlsx';
T = readtable(fname, 'TextType','string');

% ---------- 自动识别列 ----------
isNumCol = varfun(@(x) isnumeric(x), T, 'OutputFormat','uniform');
nameCol  = find(~isNumCol, 1, 'first');
if isempty(nameCol), error('未找到样本名列'); end
dataCols = setdiff(1:width(T), nameCol);
if numel(dataCols) < 3, error('需要3列数据'); end
dataCols = dataCols(1:3);
sampleNames = string(T{:, nameCol});
metricNames = T.Properties.VariableNames(dataCols);

% ---------- 解析“材料-速度-编号” ----------
n = height(T);
material = strings(n,1);
speedVal = nan(n,1);
for i = 1:n
    s = sampleNames(i);
    parts = split(s, '-');
    if numel(parts) < 2, parts = split(s, '_'); end

    matRaw = lower(strrep(strtrim(parts(1)), " ", ""));
    if contains(matRaw,"iron"),  material(i) = "iron";
    elseif contains(matRaw,"steel"), material(i) = "steel";
    else, material(i) = parts(1);
    end

    if numel(parts) >= 2
        spnum = regexp(lower(parts(2)), '\d+(\.\d+)?', 'match', 'once');
        if ~isempty(spnum), speedVal(i) = str2double(spnum); end
    end
end
speedStr = string(speedVal) + " mm/min";
T.Material = categorical(material);
T.SpeedStr = categorical(speedStr);

% ---------- 绘图参数 ----------
wantSpeeds    = [10, 50];
wantSpeedLbl  = string(wantSpeeds) + " mm/min";
wantMaterials = categorical(["iron","steel"]);
barColors = [1.00 0.70 0.70; 0.40 0.60 0.95];

outdir = "fig_out";
if ~exist(outdir,'dir'), mkdir(outdir); end

% ---------- 收集 t 检验结果（写 CSV 用） ----------
rows = {};  % 每行：Contrast, Subset, Group1, Group2, N1, N2, Mean1, SD1, Mean2, SD2, p, Signif, Test, t, df

for k = 1:numel(metricNames)
    colname   = metricNames{k};
    y         = T{:, colname};

    % 指标显示/符号/单位
    [dispName, symbol, unit] = metric_meta(colname);
    if unit ~= ""
        yLabelTxt = sprintf('%s (%s)', symbol, unit);
    else
        yLabelTxt = char(symbol);
    end
    key = metric_key(colname); % 用于 CSV 第一列（E / sigma_s / sigma_UTS / …）

    % ---- A) 同一材料下的 10 vs 50（Speed 比较）----
    mats = categories(T.Material);
    for m = 1:numel(mats)
        mat = mats{m};
        x1 = y(T.Material==mat & T.SpeedStr==wantSpeedLbl(1)); x1 = x1(~isnan(x1));
        x2 = y(T.Material==mat & T.SpeedStr==wantSpeedLbl(2)); x2 = x2(~isnan(x2));
        if ~isempty(x1) && ~isempty(x2)
            % 统计
            [~, p, ~, stats] = ttest2(x1, x2, 'Vartype','unequal');
            n1 = numel(x1); n2 = numel(x2);
            m1 = mean(x1,'omitnan'); s1 = std(x1,0,'omitnan');
            m2 = mean(x2,'omitnan'); s2 = std(x2,0,'omitnan');
            rows(end+1,:) = {sprintf('Speed-%s', key), char(prettyMat(mat)), ...
                '10 mm/min','50 mm/min', n1,n2, m1,s1, m2,s2, p, p2star(p), 'Welch t-test', stats.tstat, stats.df};

            % 绘图
            ttl = sprintf('T Test of %s of %s', dispName, prettyMat(mat));
            f = bar_welch_plot(x1, x2, string(wantSpeedLbl), yLabelTxt, ttl, barColors);
            saveas(f, fullfile(outdir, sprintf('%s_%s_10vs50.png', ...
                sanitize(colname), sanitize(mat))));
            close(f);
        end
    end

    % ---- B) 同一速度下的 iron vs steel（Material 比较）----
    for s = 1:numel(wantSpeedLbl)
        sp = wantSpeedLbl(s);
        x1 = y(T.SpeedStr==sp & T.Material==wantMaterials(1)); x1 = x1(~isnan(x1)); % iron
        x2 = y(T.SpeedStr==sp & T.Material==wantMaterials(2)); x2 = x2(~isnan(x2)); % steel
        if ~isempty(x1) && ~isempty(x2)
            [~, p, ~, stats] = ttest2(x1, x2, 'Vartype','unequal');
            n1 = numel(x1); n2 = numel(x2);
            m1 = mean(x1,'omitnan'); s1 = std(x1,0,'omitnan');
            m2 = mean(x2,'omitnan'); s2 = std(x2,0,'omitnan');
            rows(end+1,:) = {sprintf('Material-%s', key), char(sp), ...
                'iron','steel', n1,n2, m1,s1, m2,s2, p, p2star(p), 'Welch t-test', stats.tstat, stats.df};

            ttl = sprintf('T Test of %s at %s', dispName, sp);
            f = bar_welch_plot(x1, x2, cellstr(string(wantMaterials)), yLabelTxt, ttl, barColors);
            sp_token = slugify(sp); % "10 mm/min" -> "10mm_min"
            saveas(f, fullfile(outdir, sprintf('%s_%s_iron_vs_steel.png', ...
                sanitize(colname), sp_token)));
            close(f);
        end
    end
end

% ---------- 写 CSV ----------
if ~isempty(rows)
    summaryTbl = cell2table(rows, 'VariableNames', ...
        {'Contrast','Subset','Group1','Group2','N1','N2','Mean1','SD1','Mean2','SD2','p_value','Significance','Test','t','df'});
    % 可选：四舍五入展示
    summaryTbl.p_value = round(summaryTbl.p_value, 6);
    summaryTbl.Mean1   = round(summaryTbl.Mean1, 6);
    summaryTbl.Mean2   = round(summaryTbl.Mean2, 6);
    summaryTbl.SD1     = round(summaryTbl.SD1, 6);
    summaryTbl.SD2     = round(summaryTbl.SD2, 6);
    writetable(summaryTbl, fullfile(outdir, 'ttest_summary.csv'));
    fprintf('已写出 CSV：%s\n', fullfile(outdir, 'ttest_summary.csv'));
else
    warning('没有可写入 CSV 的比较结果（数据缺失或分组为空）。');
end

fprintf('完成。图像与 CSV 已保存到：%s\n', outdir);
end

% =================== 绘图与工具函数 ===================

function f = bar_welch_plot(x1, x2, xlabels, yLabelTxt, titleTxt, barColors)
m  = [mean(x1,'omitnan'), mean(x2,'omitnan')];
sd = [std(x1,0,'omitnan'), std(x2,0,'omitnan')];

f = figure('Color','w','Position',[100 100 720 520]);
b = bar(1:2, m, 'FaceColor','flat'); hold on;
b.CData(1,:) = barColors(1,:); b.CData(2,:) = barColors(2,:);
errorbar(1:2, m, sd, 'k', 'LineStyle','none', 'LineWidth',1.2);

set(gca,'XTick',1:2,'XTickLabel',xlabels,'FontSize',12);
ylabel(yLabelTxt,'FontSize',13);
title(titleTxt,'FontSize',14,'FontWeight','bold');
box on; grid on;

[~, p] = ttest2(x1, x2, 'Vartype','unequal');

yTop = max(m+sd); yMin = min([0, m-sd]);
yBar = yTop + 0.08*(yTop - yMin + eps);
plot([1 1 2 2], [yBar yBar*1.02 yBar*1.02 yBar], 'k', 'LineWidth',1.2);
text(1.5, yBar*1.05, p2star(p), 'HorizontalAlignment','center', ...
    'FontSize',13,'Interpreter','tex');

legendTxt = {'* p < 0.05', '** p < 0.01', '*** p < 0.001', 'N.S., p \geq 0.05'};
text(0.98, 0.96, legendTxt, 'Units','normalized', ...
    'HorizontalAlignment','right','VerticalAlignment','top', ...
    'FontSize',11, 'Interpreter','tex');

yl = ylim(gca);
yl(2) = max([yl(2), yBar*1.15]);
yl(1) = min([yl(1), yMin]);
ylim(yl);

n1 = numel(x1); n2 = numel(x2);
text(0.5, 0.02, sprintf('n = %d        n = %d', n1, n2), ...
    'Units','normalized','HorizontalAlignment','center','FontSize',9);
end

function s = p2star(p)
if p < 1e-3, s = '***';
elseif p < 1e-2, s = '**';
elseif p < 5e-2, s = '*';
else, s = 'N.S.';
end
end

function [dispName, symbol, unit] = metric_meta(vname)
vn = string(vname);
vnC = lower(regexprep(char(vn), '\s+', ''));

% Young's Modulus
if contains(vnC,"young") || ~isempty(regexp(vnC,'(^e$)|(^e_?g?p?a?$)','once'))
    dispName = "Young's Modulus"; symbol = 'E'; unit = 'GPa'; return;
end
% Yield Strength（含 Rp0.2 常用别名）
if contains(vnC,"yield") || contains(vnC,"sigma_s") || contains(vnC,"sigmas") || ...
   contains(vnC,"sigma_y") || contains(vnC,"s_y") || contains(vnC,"ys") || ...
   ~isempty(regexp(vnC,'^rp0?\.?2$|^rp_?0?_?2$|^rp02$','once'))
    dispName = 'Yield Strength'; symbol = '\sigma_y'; unit = 'MPa'; return;
end
% UTS
if contains(vnC,"uts") || contains(vnC,"ultimate") || contains(vnC,"tensile") || ...
   contains(vnC,"sigma_uts") || contains(vnC,"sigmab") || contains(vnC,"sigma_b")
    dispName = 'Ultimate Tensile Strength'; symbol = '\sigma_{UTS}'; unit = 'MPa'; return;
end

dispName = prettify(vn); symbol = prettify(vn); unit = '';
end

function key = metric_key(vname)
% 供 CSV 第一列使用的短键：E / sigma_s / sigma_UTS / (fallback: 原列名)
vn = string(vname);
vnC = lower(regexprep(char(vn), '\s+', ''));
if contains(vnC,"young") || ~isempty(regexp(vnC,'(^e$)|(^e_?g?p?a?$)','once'))
    key = "E"; return;
end
if contains(vnC,"yield") || contains(vnC,"sigma_s") || contains(vnC,"sigmas") || ...
   contains(vnC,"sigma_y") || contains(vnC,"s_y") || contains(vnC,"ys") || ...
   ~isempty(regexp(vnC,'^rp0?\.?2$|^rp_?0?_?2$|^rp02$','once'))
    key = "sigma_s"; return;
end
if contains(vnC,"uts") || contains(vnC,"ultimate") || contains(vnC,"tensile") || ...
   contains(vnC,"sigma_uts") || contains(vnC,"sigmab") || contains(vnC,"sigma_b")
    key = "sigma_UTS"; return;
end
key = string(vname);  % 兜底：原列名
end

function t = prettify(vname)
v = char(vname);
v = regexprep(v,'_',' ');
t = regexprep(lower(v),'(\<[a-z])','${upper($1)}');
end

function s = prettyMat(mat)
mat = string(mat);
if lower(mat)=="iron",  s = "Cast Iron";
elseif lower(mat)=="steel", s = "Steel";
else, s = prettify(mat);
end
end

function s = sanitize(strIn)
s = regexprep(char(strIn), '\s+', '');
s = regexprep(s, '[^\w\-\.]', '');
end

function s = slugify(strIn)
% 将“10 mm/min”等标签转为文件名安全片段：10mm_min
s = char(strIn);
s = regexprep(s, '\s+', '');
s = regexprep(s, '[\/\\:\*\?"\<\>\|]+', '_');
s = regexprep(s, '[^A-Za-z0-9_\-\.]+', '');
end
