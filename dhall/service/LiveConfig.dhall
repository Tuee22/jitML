{ logLevel : < Debug | Info | Warn | Error >
, retryPolicy :
    < Once
    | LinearN : { attempts : Natural, delayMillis : Natural }
    | ExponentialN : { attempts : Natural, baseMillis : Natural, capMillis : Natural }
    | RetryUntil : { deadlineMillis : Natural }
    >
, tartIdleTimeout : Optional Natural
, inferenceBatchSize : Natural
, inferenceMaxLatencyMillis : Natural
, drainDeadlineSeconds : Natural
}
