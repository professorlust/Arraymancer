# Copyright 2017 the Arraymancer contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import  ../private/[nested_containers, ast_utils],
        ./backend/metadataArray,
        ./private/p_checks,
        ./private/p_init_cpu,
        ./data_structure,
        ./operators_blas_l2l3,
        sequtils

#################################################
## Operations fusion

# TODO: tests and all linear combination of alpha A*B + beta C
# TODO: term rewriting have Attempt to read from nil bugs when not using a auto return type

proc tensor_multiplyAdd[T](
  A, B: Tensor[T],
  C: Tensor[T]): Tensor[T] =

  result = C

  if C.rank == 2:
    gemm(1.T, A, B, 1.T, result)
  elif C.rank == 1:
    gemv(1.T, A, B, 1.T, result)
  else:
    raise newException(ValueError, "Matrix-Matrix or Matrix-Vector multiplication valid only if first Tensor is a Matrix and second is a Matrix or Vector")

proc tensor_multiplyAdd_inplace[T](
  A, B: Tensor[T],
  C: var Tensor[T]) =

  if C.rank == 2:
    gemm(1.T, A, B, 1.T, C)
  elif C.rank == 1:
    gemv(1.T, A, B, 1.T, C)
  else:
    raise newException(ValueError, "Matrix-Matrix or Matrix-Vector multiplication valid only if first Tensor is a Matrix and second is a Matrix or Vector")


template rewriteTensor_MultiplyAdd*{`*`(A,B) + C}[T](
  A, B, C: Tensor[T]): auto =
  ## Fuse ``A*B + C`` into a single operation.
  ##
  ## Operation fusion leverage the Nim compiler and should not be called explicitly.
  tensor_multiplyAdd(A, B, C)

template rewriteTensor_MultiplyAdd*{C + `*`(A,B)}[T](
  A, B, C: Tensor[T]): auto =
  ## Fuse ``C + A * B`` into a single operation.
  ##
  ## Operation fusion leverage the Nim compiler and should not be called explicitly.

  # TODO: It doesn't seem to work in this order, precedence rules?
  tensor_multiplyAdd(A, B, C)

template rewriteTensor_MultiplyAdd_inplace*{C += `*`(A,B)}[T](
  A, B: Tensor[T], C: var Tensor[T]) =
  ## Fuse ``C+=A*B`` into a single operation.
  ##
  ## Operation fusion leverage the Nim compiler and should not be called explicitly.
  tensor_multiplyAdd_inplace(A, B, C)

#################################################
## initialization

template toTensorReshapeImpl(oa: typed, shape: varargs[int]): untyped =
  let data = toSeq(flatIter(oa))
  let seq_shape = shape.toMetadataArray

  when compileOption("boundChecks"):
    check_nested_elements(seq_shape, data.len)

  var t: Tensor[type(data[0])]
  tensorCpu(seq_shape, t)
  shallowCopy(t.data, data)
  t

proc toTensorReshape(oa: string, shape: varargs[int]): auto {.noInit,noSideEffect.}=
  ## Fuse toTensor and reshape in one operation.
  ##
  ## Deal specifically with strings/seq[char]

  toTensorReshapeImpl(oa, shape)

proc toTensorReshape(oa: openarray, shape: varargs[int], dummy_bugfix: static[int] = 0): auto {.noInit,noSideEffect.}=
  ## Fuse toTensor and reshape in one operation
  ##
  # Dummy_bugfix param is necessary due to: https://github.com/nim-lang/Nim/issues/6343
  # TODO: remove 'dummy_bugfix'
  toTensorReshapeImpl(oa, shape)

template rewriteToTensorReshape*{reshape(toTensor(oa, dummy_bugfix), shape)}(
  oa: openarray,
  shape: varargs[int],
  dummy_bugfix: static[int]): auto =
  ## Fuse ``sequence.toTensor.reshape(new_shape)`` into a single operation.
  ##
  ## Operation fusion leverage the Nim compiler and should not be called explicitly.
  toTensorReshape(oa, shape, dummy_bugfix)

