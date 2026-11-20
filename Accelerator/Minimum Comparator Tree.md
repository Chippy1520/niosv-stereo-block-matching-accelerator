# Minimum Comparator Tree
#implemented
The [[Minimum Comparator Tree - Code Walkthrough|pipelined comparator RTL]] reduces valid `(SAD, disparity)` tuples and is reused inside the implemented [[SAD Search Backend]]. Smaller SAD wins; on ties, smaller disparity wins. Invalid lanes, including padded leaves, cannot win; an all-invalid beat has `valid_o=0`. For 32 lanes, five registered pairwise levels accept one aligned candidate set per clock. The backend supplies common-interior qualification and aligned winner tags. Standalone callers must still align candidates; autonomous row-drain control and cross-group merge remain separate work in [[Project Plan#Disparity bank|the search plan]].

Output is disparity, not metric depth. Depth requires focal length, baseline and calibrated rectification; zero disparity must be handled explicitly. See [[Timing and Pipelining]] and [[Verification Map]].
