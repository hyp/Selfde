//
//  debuggerUtils.swift
//  Selfde
//

// Processes the debugger resume commands and extracts concrete actions for all of the given threads.
func extractResumeActionsForThreads(threads: [ThreadID], primaryThread: ThreadID, entries: [ThreadResumeEntry], defaultAction: ThreadResumeAction) -> [(ThreadID, ThreadResumeAction, COpaquePointer?)] {
    var results = [ThreadID: (ThreadID, ThreadResumeAction, COpaquePointer?)]()
    for entry in entries {
        switch entry.thread {
        case .ID(let threadID):
             results[threadID] = (threadID, entry.action, entry.address)
        case .Any:
            let threadID = primaryThread
            guard results[threadID] == nil else { continue }
            results[threadID] = (threadID, entry.action, entry.address)
        case .All:
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
