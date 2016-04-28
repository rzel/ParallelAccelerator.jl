#=
Copyright (c) 2015, Intel Corporation
All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:
- Redistributions of source code must retain the above copyright notice, 
  this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, 
  this list of conditions and the following disclaimer in the documentation 
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF 
THE POSSIBILITY OF SUCH DAMAGE.
=#

baremodule Lib

using Base
import Base: call, (==), copy

using ..cartesianmapreduce, ..cartesianarray, ..sum, ..(.*)

type MT{T}
  val :: T
  idx :: Int
end

function ==(x::MT, y::MT)
  x.val == y.val && x.idx == y.idx
end

function copy(x::MT)
  MT(x.val, x.idx)
end

@inline function indmin{T<:Number}(A::DenseArray{T})
  m = MT(A[1], 1)
  cartesianmapreduce((length(A),), 
    (x -> begin 
            if m.val > x.val 
              m.val = x.val
              m.idx = x.idx
            end
            return m
          end, 
     m)) do i
    if A[i] < m.val
      m.val = A[i]
      m.idx = i
    end
    0
  end
  return m.idx
end

@inline function indmax{T<:Number}(A::DenseArray{T})
  m = MT(A[1], 1)
  cartesianmapreduce((length(A),), 
    (x -> begin 
            if m.val < x.val 
              m.val = x.val
              m.idx = x.idx
            end
            return m
          end, 
     m)) do i
    if A[i] > m.val
      m.val = A[i]
      m.idx = i
    end
    0
  end
  return m.idx
end

@inline function sumabs2(A::DenseArray)
  sum(A .* A)
end

@inline function diag(A::DenseMatrix)
  d = min(size(A, 1), size(A, 2))
  cartesianarray(eltype(A), (d,)) do i
     A[i, i]
  end
end

@inline function diagm(A::DenseVector)
  d = size(A, 1)
  cartesianarray(eltype(A), (d, d)) do i, j
    # the assignment below is a hack to avoid mutiple return in body
    v = i == j ? A[i] : zero(eltype(A))
  end
end

@inline function trace(A::DenseMatrix)
  sum(diag(A))
end

@inline function scale(A::DenseMatrix, b::DenseVector)
  m, n = size(A)
  cartesianarray(eltype(A), (m, n)) do i, j
    A[i,j] * b[j]
  end
end

@inline function scale(b::DenseVector, A::DenseMatrix)
  m, n = size(A)
  cartesianarray(eltype(A), (m, n)) do i, j
    b[i] * A[i,j] 
  end
end

@inline function eye(m::Int, n::Int)
  cartesianarray(Float64, (m, n)) do i, j
    # the assignment below is a hack to avoid mutiple return in body
    v = i == j ? 1.0 : 0.0
  end
end

@inline function eye(m::Int)
  eye(m, m)
end

@inline function eye(A::DenseMatrix)
  eye(size(A, 1), size(A, 2))
end

@inline function repmat(A::DenseVector, m::Int, n::Int)
  s = size(A, 1)
  cartesianarray(eltype(A), (m * s, n)) do i, j
    A[1 + mod(i - 1, s)]
  end
end

@inline function repmat(A::DenseMatrix, m::Int, n::Int)
  s, t = size(A)
  cartesianarray(eltype(A), (m * s, n * t)) do i, j
    A[1 + mod(i - 1, s), 1 + mod(j - 1, t)]
  end
end

@inline function repmat(A::DenseVector, m::Int)
  repmat(A, m, 1)
end

@inline function repmat(A::DenseMatrix, m::Int)
  repmat(A, m, 1)
end

export indmin, indmax, sumabs2
export diag, diagm, trace, scale, eye, repmat 

end
