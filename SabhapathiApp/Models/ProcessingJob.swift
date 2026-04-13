import Foundation

struct ProcessingJob: Identifiable {
    let id: String  // backend job_id
    let projectId: UUID
    var status: JobState
    var progress: Double
    var message: String

    enum JobState: String {
        case queued
        case processing
        case completed
        case failed
    }
}
