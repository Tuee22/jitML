< DenseOp
| IdentityOp
| DropoutOp : Double
| ConvOp :
    { convIn : Natural
    , convOut : Natural
    , convInputDims : List Natural
    , convKernelDims : List Natural
    , convStride : List Natural
    , convPadding : List Natural
    }
| PoolOp :
    { shape : { spC : Natural, spH : Natural, spW : Natural }
    , pool :
        < PoolMax :
            { pwKh : Natural
            , pwKw : Natural
            , pwSh : Natural
            , pwSw : Natural
            , pwPh : Natural
            , pwPw : Natural
            , pwCountPad : Bool
            }
        | PoolAvg :
            { pwKh : Natural
            , pwKw : Natural
            , pwSh : Natural
            , pwSw : Natural
            , pwPh : Natural
            , pwPw : Natural
            , pwCountPad : Bool
            }
        | PoolGlobal
        >
    }
| NormOp :
    { nFlavor : < NormBatch | NormLayerWise | NormGroup : Natural >
    , nChannels : Natural
    , nSpatial : Natural
    , nEps : Double
    }
| AttentionOp :
    { attnSeqLen : Natural
    , attnEmbedDim : Natural
    , attnNumHeads : Natural
    , attnCausal : Bool
    }
| GeGLUOp : { ggIn : Natural, ggFf : Natural, ggOut : Natural }
| PatchOp :
    { peC : Natural
    , peH : Natural
    , peW : Natural
    , peP : Natural
    , peStride : Natural
    , peD : Natural
    }
| ResidualOp :
    { inner : { asIn : Natural, asOut : Natural }
    , shortcut :
        < IdentityShortcut
        | ProjectionShortcut : { asIn : Natural, asOut : Natural }
        >
    , scale : Double
    , innerActivation :
        < LinearActivation
        | TanhActivation
        | ReluActivation
        | SoftmaxActivation
        >
    }
| BlockOp :
    { blStages :
        List
          { bsAffine : { asIn : Natural, asOut : Natural }
          , bsNorm :
              Optional
                { nFlavor : < NormBatch | NormLayerWise | NormGroup : Natural >
                , nChannels : Natural
                , nSpatial : Natural
                , nEps : Double
                }
          , bsAct :
              < LinearActivation
              | TanhActivation
              | ReluActivation
              | SoftmaxActivation
              >
          }
    , blShortcut :
        < IdentityShortcut
        | ProjectionShortcut : { asIn : Natural, asOut : Natural }
        >
    , blScale : Double
    , blFinalAct :
        < LinearActivation
        | TanhActivation
        | ReluActivation
        | SoftmaxActivation
        >
    }
>
