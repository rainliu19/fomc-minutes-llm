function label = cutoffLabel(releaseDate, cfg)
%CUTOFFLABEL Label meetings by whether the model could have seen them in training.
%   label = fomc.leak.cutoffLabel(releaseDate, cfg), using cfg.modelCutoff:
%     "before_cutoff"  released on or before the cutoff
%     "near_cutoff"    within cfg.cutoffBufferDays after it (cutoffs are soft)
%     "after_cutoff"   later: the only clean meetings
%     "unverified"     cutoff not set
%   Report results by group: before_cutoff results can look better than they are.

arguments
    releaseDate datetime
    cfg (1,1) struct
end

% No cutoff set means nothing can be called clean
label = strings(size(releaseDate));
if isnat(cfg.modelCutoff)
    label(:) = "unverified";
    return
end
% Start with everything after the cutoff, then mark the near and earlier ones
label(:) = "after_cutoff";
label(releaseDate <= cfg.modelCutoff + days(cfg.cutoffBufferDays)) = "near_cutoff";
label(releaseDate <= cfg.modelCutoff) = "before_cutoff";
end
