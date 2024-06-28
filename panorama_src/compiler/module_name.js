"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.moduleName = moduleName;
function isNormal(module) {
    return 'rawRequest' in module;
}
function privateId(id) {
    return `_/${id}`;
}
const modules = new Map();
function removeExtention(path) {
    return path.replace(/(?<=[^/]+)(?:\.\w+)+/, '');
}
function ownId(path) {
    return removeExtention(path.replace(/^\.\//, ''));
}
function getModuleData(module) {
    let data = modules.get(module);
    if (!data) {
        if (isNormal(module)) {
            if (module.issuer) {
                if (module.rawRequest.startsWith('./')) {
                    const issuerData = getModuleData(module.issuer);
                    data = {
                        id: issuerData.own ? ownId(module.rawRequest) : false,
                        own: issuerData.own,
                    };
                }
                else {
                    data = {
                        id: removeExtention(module.rawRequest),
                        own: false,
                    };
                }
            }
            else {
                data = {
                    id: ownId(module.rawRequest),
                    own: true,
                };
            }
        }
        else {
            data = {
                id: false,
                own: module.issuer != undefined,
            };
        }
        modules.set(module, data);
    }
    return data;
}
function publicId(id, module) {
    return getModuleData(module).id || privateId(id);
}
function moduleName(id, module) {
    if (!id)
        return;
    const name = publicId(id, module);
    console.log(name);
    return name;
}
