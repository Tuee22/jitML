{ substrate : Text
, residency : < Cluster | Host >
, inferenceMode : < SelfInference | ForwardToHost >
, pulsarServiceUrl : Text
, pulsarAdminUrl : Text
, minioEndpoint : Text
, harborRegistry : Text
, httpListener : Optional { host : Text, port : Natural }
}
