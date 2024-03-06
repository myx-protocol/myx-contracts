module.exports = {
    allowUnlimitedContractSize: true,
    configureYulOptimizer: true,
    skipFiles: ['mock', 'openzeeplin'],
    solcOptimizerDetails: {
        peephole: false,
        inliner: false,
        jumpdestRemover: false,
        orderLiterals: true,
        deduplicate: false,
        cse: false,
        constantOptimizer: false,
        yul: false,
      },
};
