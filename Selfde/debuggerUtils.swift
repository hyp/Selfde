//
//  debuggerUtils.swift
//  Selfde
//

// Processes the debugger resume commands and extracts concrete actions for all of the given threads.
public func extractResumeActionsForThreads(_ threads: [ThreadID], primaryThread: ThreadID, entries: [ThreadResumeEntry], defaultAction: ThreadResumeAction) -> [(ThreadID, ThreadResumeAction, Address?)] {
    var results = [ThreadID: (ThreadID, ThreadResumeAction, Address?)]()
    for entry in entries {
        switch entry.thread {
        case .id(let threadID):
             results[threadID] = (threadID, entry.action, entry.address)
        case .any:
            let threadID = primaryThread
            guard results[threadID] == nil else { continue }
            results[threadID] = (threadID, entry.action, entry.address)
        case .all:
            for threadID in threads {
                results[threadID] = (threadID, entry.action, entry.address)
            }
        }
    }
    for threadID in threads {
        guard results[threadID] == nil else { continue }
        results[threadID] = (threadID, defaultAction, nil)
    }
    return Array(results.values)
}
