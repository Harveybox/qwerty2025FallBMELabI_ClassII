%% Stress–strain (Excel, 6 samples) — robust elastic fit + cross-sample consistency + 0.2% offset
clc; clear; close all;

% ===== EDIT THESE FOUR ONLY =====
FILE  = "C:\Users\usayz\Desktop\生医工实验\qwerty2025FallBMELabI_ClassII\Lab2_1\Lab2_1数据汇总.xlsx";
SHEET = "iron";
D_mm  = 4.00;      % specimen diameter (mm), same for all samples
L0_mm = 50.00;     % gauge length (mm), same for all samples
% =================================

% Column mapping in Excel: Position = deformation (mm), Load = force (N)
pairs = { ...
  "PositionValue_iron_10_4","LoadValue_iron_10_4","iron-10-4"; ...
  "PositionValue_iron_10_5","LoadValue_iron_10_5","iron-10-5"; ...
  "PositionValue_iron_10_9","LoadValue_iron_10_9","iron-10-9"; ...
  "PositionValue_iron_50_6","LoadValue_iron_50_6","iron-50-6"; ...
  "PositionValue_iron_50_7","LoadValue_iron_50_7","iron-50-7"; ...
  "PositionValue_iron_50_8","LoadValue_iron_50_8","iron-50-8" ...
};

% Read Excel (compact like your demo)
opts = spreadsheetImportOptions("NumVariables", 12);
opts.Sheet     = SHEET;
opts.DataRange = "A2:L713";
opts.VariableNames = [ ...
  "LoadValue_iron_10_4","PositionValue_iron_10_4", ...
  "LoadValue_iron_10_5","PositionValue_iron_10_5", ...
  "LoadValue_iron_10_9","PositionValue_iron_10_9", ...
  "LoadValue_iron_50_6","PositionValue_iron_50_6", ...
  "LoadValue_iron_50_7","PositionValue_iron_50_7", ...
  "LoadValue_iron_50_8","PositionValue_iron_50_8" ];
opts.VariableTypes = repmat("double",1,12);
T = readtable(FILE, opts, "UseExcel", false);

% -------- Analysis config --------
cfg.OffsetStrain       = 0.002;   % 0.2% offset
cfg.TailTolerance      = 5e-5;    % cut tail when strain falls after fracture
cfg.DedupMethod        = 'mean';  % duplicate strains: 'mean'|'max'|'last'
cfg.ElasticMaxStrain   = 0.010;   % search cap: 1% strain
cfg.MinPrefixPoints    = 20;      % minimal points to begin fitting
cfg.ElasticR2Min       = 0.99;    % R^2 threshold (relaxed)
cfg.SlopeVarTol        = 0.10;    % early/late slope diff <= 10%
cfg.ConsistencyTol     = 0.20;    % |E - median(E)|/median(E) <= 20%
cfg.SmoothWindow       = 1;       % >=3: moving mean on stress only

A_mm2 = pi*(D_mm/2)^2;            % area (mm^2)
outDir = "fig_out";
if ~exist(outDir,"dir"); mkdir(outDir); end

% ---------- PASS 1: per-sample candidates & initial pick ----------
n = size(pairs,1);
Scell = cell(n,1);    % collect in cell first to avoid struct-assign errors
for i = 1:n
    name   = pairs{i,3};
    def_mm = T.(pairs{i,1});
    load_N = T.(pairs{i,2});
    Scell{i} = analyze_candidates(name, def_mm, load_N, A_mm2, L0_mm, cfg);
end
S = [Scell{:}];       % now form a struct array safely

% median E across samples (ignore NaN)
E_vals = [S.E_final];
E_vals = E_vals(isfinite(E_vals));
E_med  = median(E_vals);
if isempty(E_med), E_med = mean(E_vals); end  % extremely defensive

% ---------- PASS 2: harmonize to median if deviating too much ----------
for i = 1:numel(S)
    if isfinite(E_med) && isfinite(S(i).E_final) ...
       && abs(S(i).E_final - E_med)/max(E_med,eps) > cfg.ConsistencyTol

        okIdx = find(S(i).ok_list);
        if ~isempty(okIdx)
            [~, t] = min(abs(S(i).E_list(okIdx) - E_med));
            pickIdx = okIdx(t);
        else
            [~, pickIdx] = min(abs(S(i).E_list - E_med));
        end

        % update pick
        S(i).E_final      = S(i).E_list(pickIdx);
        S(i).R2_final     = S(i).R2_list(pickIdx);
        S(i).N_final      = S(i).N_list(pickIdx);
        S(i).eps_fit_end  = S(i).eps_list(pickIdx);
        % recompute yield using updated slope
        [S(i).eps_y, S(i).sig_y] = yield_with_E(S(i).e, S(i).s, S(i).E_final, cfg.OffsetStrain);
    end
end

% ---------- Plot & save + CSV ----------
Summary = table('Size',[0 7], ...
  'VariableTypes',{'string','double','double','double','double','double','double'}, ...
  'VariableNames',{'sample','E_MPa','intercept_c_MPa','R2','yield_MPa','yield_strain','fit_strain_end'});

for i = 1:numel(S)
    name = S(i).name;

    % figure (only curve span)
    f = figure('Color','w','Name',name,'Position',[100 100 560 420]); hold on; box on; grid on; grid minor;
    % main curve
    p1 = plot(S(i).e, S(i).s, '-', 'LineWidth', 1.4, 'DisplayName','Engineering stress–strain');

    % lines drawn only over curve range
    xMax = max(S(i).e); yMax = max(S(i).s);
    xfit = linspace(0, xMax, 800);
    p2 = plot(xfit, S(i).E_final*xfit, '--', 'LineWidth', 1.2, 'DisplayName','Elastic fit');
    p3 = plot(xfit, S(i).E_final*(xfit - cfg.OffsetStrain), ':', 'LineWidth', 1.6, 'DisplayName','0.2% offset line');
    % yield point
    p4 = plot(S(i).eps_y, S(i).sig_y, 'p', 'MarkerSize', 11, 'MarkerFaceColor',[0.85 0.2 0.2], ...
        'DisplayName', sprintf('Yield point \\sigma_y=%.0f MPa', S(i).sig_y));

    xlabel('Engineering strain \epsilon');  % no unit
    ylabel('Engineering stress \sigma (MPa)');
    title(name, 'Interpreter','none');
    ax = gca; ax.XAxis.Exponent = 0; ax.YAxis.Exponent = 0;
    xlim([0, xMax*1.02]); ylim([0, yMax*1.05]);
    xtickformat('%.4f'); ytickformat('%.0f');
    legend([p1 p2 p3 p4],'Location','best');

    exportgraphics(f, fullfile(outDir, name + ".png"), 'Resolution', 300);

    % CSV row (equation via slope E and intercept c=0)
    Summary = [Summary; {string(name), S(i).E_final, 0, S(i).R2_final, S(i).sig_y, S(i).eps_y, S(i).eps_fit_end}]; %#ok<AGROW>
end

writetable(Summary, fullfile(outDir, "tensile_summary.csv"));
disp("Saved images and CSV to: " + outDir);
disp(Summary);

%% ===================== helper functions =====================
function Z = analyze_candidates(name, def_mm, load_N, A_mm2, L0_mm, cfg)
    % ---- basic clean ----
    m = isfinite(def_mm) & isfinite(load_N);
    def_mm = def_mm(m); load_N = load_N(m);

    % ensure column vectors
    def_mm = def_mm(:); load_N = load_N(:);

    % engineering strain & stress
    e = def_mm / L0_mm;     % —
    s = load_N / A_mm2;     % MPa

    % cut tail when strain falls after fracture
    cm = cummax(e);
    idx_end = find(e < cm - cfg.TailTolerance, 1, 'first');
    if isempty(idx_end), idx_end = numel(e); end
    e = e(1:idx_end); s = s(1:idx_end);

    % optional smoothing (stress only)
    if cfg.SmoothWindow >= 3
        s = smoothdata(s, 'movmean', cfg.SmoothWindow);
    end

    % deduplicate by strain (unique & increasing)
    [e, s] = dedup(e, s, cfg.DedupMethod);

    % ---- candidate prefixes within 0–ElasticMaxStrain ----
    capIdx = find(e <= cfg.ElasticMaxStrain);
    if isempty(capIdx)
        capN = numel(e);
    else
        capN = capIdx(end);
    end
    minN = min(max(cfg.MinPrefixPoints,5), capN);
    if capN < 2
        % degenerate fallback: use all points
        Ei = (e'*s)/(e'*e + 1e-12);  R2i = 0;  N = numel(e);
        E_list = Ei; R2_list = R2i; N_list = N; eps_end_list = e(end); ok_list = true;
    else
        tCount = max(capN - minN + 1, 1);
        E_list  = zeros(1, tCount);
        R2_list = zeros(1, tCount);
        N_list  = zeros(1, tCount);
        eps_end_list = zeros(1, tCount);
        ok_list = false(1, tCount);

        t = 0;
        for N = minN:capN
            t = t + 1;
            ei = e(1:N); si = s(1:N);
            % through-origin LS: sigma ≈ E * epsilon
            Ei = (ei'*si) / (ei'*ei + 1e-12);
            yhat = Ei*ei;
            SSres = sum((si - yhat).^2);
            SStot = sum((si - mean(si)).^2) + 1e-12;
            R2i = 1 - SSres/SStot;

            % slope stability: first half vs second half
            k = max(floor(N/2),1);
            E_early = (ei(1:k)'*si(1:k)) / (ei(1:k)'*ei(1:k) + 1e-12);
            E_late  = (ei(k+1:end)'*si(k+1:end)) / (ei(k+1:end)'*ei(k+1:end) + 1e-12);
            slope_ok = abs(E_late - E_early) <= cfg.SlopeVarTol * max(E_early,1e-12);

            E_list(t)       = Ei;
            R2_list(t)      = R2i;
            N_list(t)       = N;
            eps_end_list(t) = ei(end);
            ok_list(t)      = (R2i >= cfg.ElasticR2Min) && slope_ok;
        end
    end

    % choose longest ok; if none ok, take best R2
    okIdx = find(ok_list);
    if ~isempty(okIdx)
        [~, j] = max(N_list(okIdx));
        pickIdx = okIdx(j);                 % <<< FIX: pick a single scalar index
    else
        [~, pickIdx] = max(R2_list);
    end

    E = E_list(pickIdx); c = 0; R2 = R2_list(pickIdx);
    [eps_y, sig_y] = yield_with_E(e, s, E, cfg.OffsetStrain);

    Z = struct('name',name,'e',e,'s',s, ...
        'E_list',E_list,'R2_list',R2_list,'N_list',N_list,'eps_list',eps_end_list,'ok_list',logical(ok_list), ...
        'E_final',E,'R2_final',R2,'N_final',N_list(pickIdx),'eps_fit_end',eps_end_list(pickIdx), ...
        'eps_y',eps_y,'sig_y',sig_y);
end

function [eps_y, sig_y] = yield_with_E(e, s, E, e0)
    % E must be scalar; e,s are column vectors
    d = s - (E .* (e - e0));
    k = find(d(1:end-1).*d(2:end) < 0, 1, 'first');   % strict sign change
    if isempty(k)
        k = find((d(1:end-1)<=0 & d(2:end)>=0) | (d(1:end-1)>=0 & d(2:end)<=0), 1, 'first');
    end
    if isempty(k)
        [~,kmin] = min(abs(d)); eps_y = e(kmin); sig_y = s(kmin);
    else
        eps_y = interp1(d(k:k+1), e(k:k+1), 0, 'linear');
        sig_y = interp1(e(k:k+1), s(k:k+1), eps_y, 'linear');
    end
end

function [xu, yu] = dedup(x, y, how)
    % make x unique & increasing by grouping identical x's
    [~,~,g] = unique(x,'stable');
    switch lower(how)
        case 'max',  yu = accumarray(g, y, [], @max);
        case 'last', yu = accumarray(g, y, [], @(v) v(end));
        otherwise,   yu = accumarray(g, y, [], @mean);
    end
    xu = accumarray(g, x, [], @(v) v(1));
end
