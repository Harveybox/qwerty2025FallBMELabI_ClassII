%% Low-carbon steel: stress–strain (Excel) + elastic prefix fit + upper/lower yield by extrema
clc; clear; close all;

% ===== EDIT THESE THREE ONLY =====
FILE  = "C:\Users\usayz\Desktop\生医工实验\qwerty2025FallBMELabI_ClassII\Lab2_1\Lab2_1数据汇总.xlsx";   % <== your Excel file
SHEET = "steel";                             % <== sheet name
D_mm  = 4.00;                               % specimen diameter (mm)
L0_mm = 50.00;                              % gauge length (mm)
                           % gauge length (mm)
% =================================

% Column mapping: Position = deformation (mm), Load = force (N)
% Your latest names: steel_10_(1,2,4) and steel_50_(5,6,7)
pairs = { ...
  "PositionValue_steel_10_1","LoadValue_steel_10_1","steel-10-1"; ...
  "PositionValue_steel_10_2","LoadValue_steel_10_2","steel-10-2"; ...
  "PositionValue_steel_10_4","LoadValue_steel_10_4","steel-10-4"; ...
  "PositionValue_steel_50_5","LoadValue_steel_50_5","steel-50-5"; ...
  "PositionValue_steel_50_6","LoadValue_steel_50_6","steel-50-6"; ...
  "PositionValue_steel_50_7","LoadValue_steel_50_7","steel-50-7" ...
};

% Read Excel (compact)
opts = spreadsheetImportOptions("NumVariables", 12);
opts.Sheet     = SHEET;
opts.DataRange = "A2:L713";
opts.VariableNames = [ ...
  "LoadValue_steel_10_1","PositionValue_steel_10_1", ...
  "LoadValue_steel_10_2","PositionValue_steel_10_2", ...
  "LoadValue_steel_10_4","PositionValue_steel_10_4", ...
  "LoadValue_steel_50_5","PositionValue_steel_50_5", ...
  "LoadValue_steel_50_6","PositionValue_steel_50_6", ...
  "LoadValue_steel_50_7","PositionValue_steel_50_7" ];
opts.VariableTypes = repmat("double",1,12);
T = readtable(FILE, opts, "UseExcel", false);

% -------- Analysis config --------
cfg.TailTolerance      = 5e-5;    % cut tail when strain falls after fracture
cfg.DedupMethod        = 'mean';  % duplicate strains: 'mean'|'max'|'last'
cfg.ElasticMaxStrain   = 0.010;   % search cap: 1% strain
cfg.MinPrefixPoints    = 20;      % minimal points to begin fitting
cfg.ElasticR2Min       = 0.99;    % R^2 threshold
cfg.SlopeVarTol        = 0.10;    % early/late slope diff <= 10%
cfg.ConsistencyTol     = 0.20;    % |E - median(E)|/median(E) <= 20%
cfg.SmoothWindow       = 1;       % >=3: moving mean on stress (for noise)

% Yield/plateau (refined, NO findpeaks)
cfg.SmoothYieldWin     = 11;      % smoothing for yield logic (odd)
cfg.UpperBacktrackPts  = 5;       % search σ_u window starts a few points BEFORE N0
cfg.UpperSearchPts     = 60;      % and extends this many points AFTER N0
cfg.YieldDropFrac      = 0.02;    % confirm yielding if min after N0 drops by ≥2% of σ_u
cfg.FirstValleyWinPts  = 30;      % window to capture/skip the first deep valley after σ_u
cfg.PostValleyGuardPts = 8;       % extra guard points after that first valley
cfg.PlateauWindowFrac  = 0.25;    % search lower-yield minimum within this fraction of remaining curve
cfg.PlateauMinPts      = 25;      % minimal number of points for plateau search

% Fracture detection
cfg.FractureDropFrac   = 0.05;    % last stress must be < (1-5%) of global max
cfg.FractureNegSlopeK  = 8;       % last K-point average slope must be negative

A_mm2 = pi*(D_mm/2)^2;            % area (mm^2)
outDir = "fig_out_lcsteel";
if ~exist(outDir,"dir"); mkdir(outDir); end

% ---------- PASS 1: per-sample candidates & initial pick ----------
n = size(pairs,1);
Scell = cell(n,1);
for i = 1:n
    name   = pairs{i,3};
    def_mm = T.(pairs{i,1});
    load_N = T.(pairs{i,2});
    Scell{i} = analyze_candidates(name, def_mm, load_N, A_mm2, L0_mm, cfg);
end
S = [Scell{:}];

% median E across samples
E_vals = [S.E_final]; E_vals = E_vals(isfinite(E_vals));
E_med  = median(E_vals);
if isempty(E_med), E_med = mean(E_vals); end

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
        S(i).E_final      = S(i).E_list(pickIdx);
        S(i).R2_final     = S(i).R2_list(pickIdx);
        S(i).N_final      = S(i).N_list(pickIdx);
        S(i).eps_fit_end  = S(i).eps_list(pickIdx);
        % recompute yields & fracture with new elastic end
        [S(i).has_yield, S(i).eps_u, S(i).sig_u, S(i).eps_l, S(i).sig_l] = ...
            yields_lowcarbon_refined(S(i).e, S(i).s, S(i).N_final, cfg);
        [S(i).has_frac, S(i).sig_f] = detect_fracture(S(i).s, cfg);
    end
end

% ---------- Plot & save + CSV ----------
Summary = table('Size',[0 9], ...
  'VariableTypes',{'string','double','double','double','double','double','double','double','double'}, ...
  'VariableNames',{'sample','E_GPa','R2','fit_strain_end', ...
                   'upper_yield_MPa','upper_yield_strain', ...
                   'lower_yield_MPa','lower_yield_strain', ...
                   'fracture_strength_MPa'});

for i = 1:numel(S)
    name = S(i).name;

    f = figure('Color','w','Name',name,'Position',[100 100 560 420]); hold on; box on; grid on; grid minor;
    % main curve
    plot(S(i).e, S(i).s, '-', 'LineWidth', 1.4, 'DisplayName','Engineering stress–strain');

    % elastic fit
    xMax = max(S(i).e); yMax = max(S(i).s);
    xfit = linspace(0, xMax, 800);
    plot(xfit, S(i).E_final*xfit, '--', 'LineWidth', 1.2, 'DisplayName','Elastic fit');

    % yields
    if S(i).has_yield
        plot(S(i).eps_u, S(i).sig_u, 'p', 'MarkerSize', 11, 'MarkerFaceColor',[0.85 0.4 0.1], ...
             'DisplayName', sprintf('Upper yield \\sigma_u=%.0f MPa', S(i).sig_u));
        plot(S(i).eps_l, S(i).sig_l, 'p', 'MarkerSize', 11, 'MarkerFaceColor',[0.3 0.3 0.85], ...
             'DisplayName', sprintf('Lower yield \\sigma_l=%.0f MPa', S(i).sig_l));
    end

    % fracture (ONLY if detected)
    if S(i).has_frac
        [~, nmax] = max(S(i).s); % for label sense
        plot(S(i).e(end), S(i).s(end), 'h', 'MarkerSize', 10, 'MarkerFaceColor',[0.2 0.6 0.2], ...
            'DisplayName', sprintf('Ultimate fracture strength \\sigma_f=%.0f MPa', S(i).sig_f));
    end

    xlabel('Engineering strain \epsilon');
    ylabel('Engineering stress \sigma (MPa)');
    title(name, 'Interpreter','none');
    ax = gca; ax.XAxis.Exponent = 0; ax.YAxis.Exponent = 0;
    xlim([0, xMax*1.02]); ylim([0, yMax*1.05]);
    xtickformat('%.4f'); ytickformat('%.0f');
    legend('Location','best');

    exportgraphics(f, fullfile(outDir, name + ".png"), 'Resolution', 300);

    % CSV row (E in GPa)
    Summary = [Summary; {string(name), S(i).E_final/1000, S(i).R2_final, S(i).eps_fit_end, ...
                         ternNaN(S(i).has_yield, S(i).sig_u), ternNaN(S(i).has_yield, S(i).eps_u), ...
                         ternNaN(S(i).has_yield, S(i).sig_l), ternNaN(S(i).has_yield, S(i).eps_l), ...
                         ternNaN(S(i).has_frac,  S(i).sig_f)}]; %#ok<AGROW>
end

writetable(Summary, fullfile(outDir, "tensile_summary.csv"));
disp("Saved images and CSV to: " + outDir);
disp(Summary);

%% ===================== helper functions =====================
function Z = analyze_candidates(name, def_mm, load_N, A_mm2, L0_mm, cfg)
    % clean & vectors
    m = isfinite(def_mm) & isfinite(load_N);
    def_mm = def_mm(m); load_N = load_N(m);
    def_mm = def_mm(:); load_N = load_N(:);

    % engineering
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

    % candidate prefixes
    capIdx = find(e <= cfg.ElasticMaxStrain);
    if isempty(capIdx), capN = numel(e); else, capN = capIdx(end); end
    minN = min(max(cfg.MinPrefixPoints,5), capN);

    if capN < 2 || minN > capN
        Ei = (e'*s)/(e'*e + 1e-12);  R2i = 0;  N = numel(e);
        E_list = Ei; R2_list = R2i; N_list = N; eps_end_list = e(end); ok_list = true;
    else
        tCount = capN - minN + 1;
        E_list  = zeros(1,tCount);
        R2_list = zeros(1,tCount);
        N_list  = zeros(1,tCount);
        eps_end_list = zeros(1,tCount);
        ok_list     = false(1,tCount);

        t = 0;
        for N = minN:capN
            t = t + 1;
            ei = e(1:N); si = s(1:N);
            Ei = (ei'*si)/(ei'*ei + 1e-12);  % through-origin LS
            yhat = Ei*ei;
            SSres = sum((si - yhat).^2);
            SStot = sum((si - mean(si)).^2) + 1e-12;
            R2i = 1 - SSres/SStot;

            k = max(floor(N/2),1);
            E_early = (ei(1:k)'*si(1:k))/(ei(1:k)'*ei(1:k) + 1e-12);
            E_late  = (ei(k+1:end)'*si(k+1:end))/(ei(k+1:end)'*ei(k+1:end) + 1e-12);
            slope_ok = abs(E_late - E_early) <= cfg.SlopeVarTol * max(E_early,1e-12);

            E_list(t)       = Ei;
            R2_list(t)      = R2i;
            N_list(t)       = N;
            eps_end_list(t) = ei(end);
            ok_list(t)      = (R2i >= cfg.ElasticR2Min) && slope_ok;
        end
    end

    % choose longest ok; else best R2
    okIdx = find(ok_list);
    if ~isempty(okIdx)
        [~, j] = max(N_list(okIdx)); pickIdx = okIdx(j);
    else
        [~, pickIdx] = max(R2_list);
    end

    E = E_list(pickIdx); R2 = R2_list(pickIdx); Nf = N_list(pickIdx);

    % refined yields & fracture
    [has_yield, eps_u, sig_u, eps_l, sig_l] = yields_lowcarbon_refined(e, s, Nf, cfg);
    [has_frac, sig_f] = detect_fracture(s, cfg);

    Z = struct('name',name,'e',e,'s',s, ...
        'E_list',E_list,'R2_list',R2_list,'N_list',N_list,'eps_list',eps_end_list,'ok_list',logical(ok_list), ...
        'E_final',E,'R2_final',R2,'N_final',Nf,'eps_fit_end',e(Nf), ...
        'has_yield',has_yield,'eps_u',eps_u,'sig_u',sig_u,'eps_l',eps_l,'sig_l',sig_l, ...
        'has_frac',has_frac,'sig_f',sig_f);
end

function [has_yield, eps_u, sig_u, eps_l, sig_l] = yields_lowcarbon_refined(e, s, N0, cfg)
    % Smooth a copy for robust decisions (keep original for reporting)
    n  = numel(e);
    w  = cfg.SmoothYieldWin; if w < 3, w = 3; end; if mod(w,2)==0, w = w+1; end
    ssm = smoothdata(s, 'movmean', min(w, max(3, 2*floor(n/2)-1)));

    % --- Upper yield: pick the true peak near N0 ---
    L = max(1, N0 - cfg.UpperBacktrackPts);
    R = min(n, N0 + cfg.UpperSearchPts);
    [sig_u, idx_local] = max(ssm(L:R));
    idx_u = L + idx_local - 1;
    eps_u = e(idx_u);

    % Confirm yielding exists: there must be a drop of >= YieldDropFrac after idx_u
    min_after = min(ssm(min(idx_u+1,n):min(n, idx_u + max(10, round(0.1*(n-idx_u))))));
    if (sig_u - min_after) < cfg.YieldDropFrac * max(sig_u,1e-6)
        has_yield = false; eps_l = NaN; sig_l = NaN; return;
    end
    has_yield = true;

    % --- Lower yield: ignore the 1st deep valley; then take min in stable plateau ---
    % First deep valley window right after upper yield:
    V1L = min(n, idx_u + 1);
    V1R = min(n, idx_u + cfg.FirstValleyWinPts);
    if V1L > n-2
        eps_l = e(idx_u); sig_l = s(idx_u); return;
    end
    [~, idx_first_valley_local] = min(ssm(V1L:V1R));
    idx_first_valley = V1L + idx_first_valley_local - 1;

    % Start plateau search AFTER the first valley + guard
    P0 = min(n, idx_first_valley + cfg.PostValleyGuardPts);
    P1 = min(n, P0 + max(cfg.PlateauMinPts, round(cfg.PlateauWindowFrac*(n-P0))));
    if P0 >= n
        eps_l = e(idx_first_valley); sig_l = s(idx_first_valley); return;
    end
    [sig_l, idx_plat_local] = min(ssm(P0:P1));
    idx_l = P0 + idx_plat_local - 1;

    % Report using original (unsmoothed) values at those indices
    sig_u = s(idx_u); eps_u = e(idx_u);
    sig_l = s(idx_l); eps_l = e(idx_l);
end

function [has_frac, sig_f] = detect_fracture(s, cfg)
    % Detect true fracture softening at the tail
    n = numel(s);
    [smax, imax] = max(s);
    tailMeanSlope = mean(diff(s(max(n-cfg.FractureNegSlopeK,1):n)));
    if (s(end) < (1 - cfg.FractureDropFrac)*smax) && (n > imax) && (tailMeanSlope < 0)
        has_frac = true;  sig_f = s(end);
    else
        has_frac = false; sig_f = NaN;
    end
end

function out = ternNaN(cond, val)
    if cond, out = val; else, out = NaN; end
end

function [xu, yu] = dedup(x, y, how)
    [~,~,g] = unique(x,'stable');
    switch lower(how)
        case 'max',  yu = accumarray(g, y, [], @max);
        case 'last', yu = accumarray(g, y, [], @(v) v(end));
        otherwise,   yu = accumarray(g, y, [], @mean);
    end
    xu = accumarray(g, x, [], @(v) v(1));
end