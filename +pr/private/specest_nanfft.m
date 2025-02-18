function [spectrum] = specest_nanfft(dat, time, varargin)

% SPECEST_NANFFT computes a fast Fourier transform in the presence of NaNs
% in the data
%
% Use as
%   [spectrum] = specest_nanfft(dat, ...)
%
%
%   dat      = matrix of chan*sample
%   time     = vector, containing time in seconds for each sample
%   spectrum = matrix of taper*chan*foi*toi of fourier coefficients
%
%
%
%
% Optional arguments should be specified in key-value pairs and can include:
%   basis      = precomputes set of basis functions (sines/cosines)
%   datataype  = 0, 1, 2
%
%
%
%
% FFT SPEED NOT YET OPTIMIZED (e.g. matlab version, transpose or not)
% FUNCTION IS RECURSIVE, SHOULD BE AVOIDED IN FAVOR OF TRANSPARANCY
%
%
% See also SPECEST_MTMFFT, SPECEST_TFR, SPECEST_HILBERT, SPECEST_MTMWELCH, SPECEST_MTMCONVOL, SPECEST_MVAR, SPECEST_WLTCONVOL



% Copyright (C) 2008, Robert Oostenveld
%
% This file is part of FieldTrip, see http://www.ru.nl/neuroimaging/fieldtrip
% for the documentation and details.
%
%    FieldTrip is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    FieldTrip is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with FieldTrip. If not, see <http://www.gnu.org/licenses/>.
%
% $Id: specest_nanfft.m 1159 2010-05-28 11:53:46Z roevdmei $

% get the optional arguments
basis     = keyval('basis',     varargin);
datatype  = keyval('datatype',  varargin);

% determine the data characteristics
[nchan, nsample] = size(dat);
fsample = 1/(time(2)-time(1));


if mod(nsample,2)==0
  % the number of samples is even
  k = nsample/2+1;
else
  % the number of samples is odd
  k = floor(nsample/2+1);
end

% determine the type of data and thereby the most suitable algorithm to use
nancount = sum(isnan(dat), 1);
if isempty(datatype)
  if all(nancount==0)
    % there is no missing data
    datatype = 0;
  elseif all(nancount==0 | nancount==nchan)
    % the missing data is at the same location for all channels
    datatype = 1;
  else
    % the missing data is at different timepoints for different channels
    datatype = 2;
  end
end

if datatype==0
  % no basis functions are needed, because the standard FFT routine will be used

elseif datatype~=0 && isempty(basis)
  % create a seperate set of basis functions for the cosine and sine
  basis_c = zeros(k, nsample);
  basis_s = zeros(k, nsample);

  % create the time axis
  t = linspace(0, 2*pi, nsample+1);
  t = t(1:end-1);

  for w=1:k
    c = cos((w-1)*t);
    s = sin((w-1)*t);
    if w==1 || (w==(k) && mod(nsample,2)==0)
      % the normalization for the lowest (DC) and the highest frequency component is different
      s = s/(nsample);
      c = c/(nsample);
    else
      s = s/(nsample/2);
      c = c/(nsample/2);
    end
    basis_c(w,:) = c;
    basis_s(w,:) = s;
  end
  % concatenate the sine and cosine basis functions
  % leaving the first and last sine functions out, since those are all zero
  if mod(nsample,2)==0
    % the number of samples is even -> the last sine wave basis function is zero
    basis = cat(1, basis_c, basis_s(2:end-1, :));
  else
    % the number of samples is odd -> also include the last sine wave basis function
    basis = cat(1, basis_c, basis_s(2:end, :));
  end
end


switch datatype
  case 0
    % there is no missing data
    % use the standard FFT implementation
    y = fft(dat, [], 2);

  case 1
    % the missing data is at the same location for all channels
    % remove that piece from the data and from the basis functions and use linear estimation
    
    keep = ~isnan(dat(1,:));

    if all(~keep)
      % the data is all NaN, no reason to try to estimate the basis
      % functions
      y = nan(size(dat));
      return
    end

    basis = basis(:,keep);
    dat = dat(:,keep);

    % do the linear estimation based on dat=y*basis
    % y = dat / basis;
    y = dat * pinv(basis);

    % disentagle the estimated components

    if mod(nsample,2)==0
      % the number of samples is even -> the last sine wave basis function is zero
      sel1 = 1;       % lowest cosine, i.e. DC
      sel2 = 2:(k-1); % all cosines in between
      sel3 = k;       % highest cosine
      sel4 = (k+1):nsample; % all sines

      est1 = y(:,sel1);
      est2 = y(:,sel2);
      est3 = y(:,sel3);
      est4 = y(:,sel4);

      % combine the various estimates into a complex representation compatible with standard FFT
      y_real = cat(2, est1,        est2, est3,          fliplr(est2));
      y_imag = cat(2, zeros(nchan,1), -est4, zeros(nchan,1),    fliplr(est4));
      y = y_real + i*y_imag;

    else
      % the number of samples is odd -> also include the last sine wave basis function
      sel1 = 1;       % lowest cosine, i.e. DC
      sel2 = 2:k;     % all other cosines
      sel3 = (k+1):nsample; % all sines

      est1 = y(:,sel1);
      est2 = y(:,sel2);
      est3 = y(:,sel3);

      % combine the various estimates into a complex representation compatible with standard FFT
      y_real = cat(2, est1,        est2, fliplr(est2));
      y_imag = cat(2, zeros(nchan,1), -est3, fliplr(est3));
      y = y_real + i*y_imag;
    end

  case 2
    % the missing data is at different timepoints for different channels
    % use recursion to compute the nanfft for each channel
    y = zeros(size(dat));
    for k=1:nchan
      y(k,:) = specest_nanfft(dat(k,:), 'basis', basis);
    end

  otherwise
    error('unsupported configuration of NaNs in the data');
end

% set output
spectrum = y;

