"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = expandApplyAtRules;
function expandApplyAtRules() {
    return (root)=>{
        partitionRules(root);
    };
}
function partitionRules(root) {
    if (!root.walkAtRules) return;
    let applyParents = new Set();
    root.walkAtRules("apply", (rule)=>{
        applyParents.add(rule.parent);
    });
    if (applyParents.size === 0) {
        return;
    }
    for (let rule1 of applyParents){
        let nodeGroups = [];
        let lastGroup = [];
        for (let node of rule1.nodes){
            if (node.type === "atrule" && node.name === "apply") {
                if (lastGroup.length > 0) {
                    nodeGroups.push(lastGroup);
                    lastGroup = [];
                }
                nodeGroups.push([
                    node
                ]);
            } else {
                lastGroup.push(node);
            }
        }
        if (lastGroup.length > 0) {
            nodeGroups.push(lastGroup);
        }
        if (nodeGroups.length === 1) {
            continue;
        }
        for (let group of [
            ...nodeGroups
        ].reverse()){
            let clone = rule1.clone({
                nodes: []
            });
            clone.append(group);
            rule1.after(clone);
        }
        rule1.remove();
    }
}
