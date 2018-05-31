module params
!$$$  module documentation block
!
! module: params                       read namelist for EnKF from file
!                                      enkf.nml.
!
! prgmmr: whitaker         org: esrl/psd               date: 2009-02-23
!
! abstract: This module holds the namelist parameters (and some derived
! parameters) read in from enkf.nml (by the module subroutine
! read_namelist) on each MPI task.
!
! Public Subroutines:
!   read_namelist: initialize namelist parameter defaults, read namelist
!    (over-riding defaults for parameters supplied in namelist), compute
!    some derived parameters.  Sets logical variable params_initialized
!    to .true.
!
! Public Variables: (see comments in subroutine read_namelist)
!
! Modules Used: mpisetup, constants, kinds
!
! program history log:
!   2009-02-23  Initial version.
!   2016-05-02  shlyaeva - Modification for reading state vector from table
!   2016-11-29  shlyaeva - added nhr_state (hours for state fields to 
!                          calculate Hx; nhr_anal is for IAU)
!   2018-05-31  whitaker - added neigv (for model-space localization using
!                          modulated ensembles), nobsl_max (for ob selection
!                          in LETKF, denkf (for Sakov's DEnKF), and dfs_sort
!                          (for using DFS in LETKF ob selection).
!
! attributes:
!   language: f95
!
!$$$

use mpisetup
use constants, only: rearth, deg2rad, init_constants, init_constants_derived
use kinds, only: r_single,i_kind
use radinfo, only: adp_anglebc,angord,use_edges,emiss_bc,newpc4pred

implicit none
private
public :: read_namelist
!  nsats_rad: the total number of satellite data types to read.
!  sattypes_rad:  strings describing the satellite data type (which form part
!   of the diag* filename).
!  dsis:  strings corresponding to sattypes_rad which correspond to the names
!   in the NCEP global_satinfo file.
!  sattypes_oz :  strings describing the ozone satellite data type (which form
!   part of the diag* filename).
integer(i_kind), public, parameter :: nsatmax_rad = 200
integer(i_kind), public, parameter :: nsatmax_oz = 100
character(len=20), public, dimension(nsatmax_rad) ::sattypes_rad, dsis
character(len=20), public, dimension(nsatmax_oz) ::sattypes_oz
! forecast times for first-guess forecasts to be updated (in hours)
integer,dimension(7),public ::  nhr_anal  = (/6,-1,-1,-1,-1,-1,-1/)
integer,dimension(7),public ::  nhr_state = (/6,-1,-1,-1,-1,-1,-1/)
! forecast hour at middle of assimilation window
real(r_single),public :: fhr_assim=6.0
! character string version of nhr_anal with leading zeros.
character(len=2),dimension(7),public :: charfhr_anal
character(len=2),dimension(7),public :: charfhr_state
! prefix for background and analysis file names (mem### appended)
! For global, default is "sfg_"//datestring//"_fhr##_" and
! "sanl_"//datestring//"_fhr##_". If only one time level
! in background, default for analysis is "sanl_"//datestring//"_"
! For regional, default is "firstguess_fhr##." and
! "analysis_fhr##." If only one time level
! in background, default is "firstguess." and "analysis.".
character(len=120),dimension(7),public :: fgfileprefixes
character(len=120),dimension(7),public :: statefileprefixes
character(len=120),dimension(7),public :: anlfileprefixes
! analysis date string (YYYYMMDDHH)
character(len=10), public ::  datestring
! filesystem path to input files (first-guess, GSI diagnostic files).
character(len=500),public :: datapath
! if deterministic=.true., the deterministic square-root filter
! update is used.  If .false, a perturbed obs (stochastic) update
! is used.
logical, public :: deterministic, sortinc, pseudo_rh, &
                   varqc, huber, cliptracers, readin_localization
logical, public :: lupp
integer(i_kind),public ::  iassim_order,nlevs,nanals,numiter,&
                           nlons,nlats,nbackgrounds,nstatefields
integer(i_kind),public :: nsats_rad,nsats_oz,imp_physics
! random seed for perturbed obs (deterministic=.false.)
! if zero, system clock is used.  Also used when
! iassim_order=1 (random shuffling of obs for serial assimilation).
integer(i_kind),public :: iseed_perturbed_obs = 0
real(r_single),public ::  covinflatemax,covinflatemin,smoothparm,biasvar
real(r_single),public ::  corrlengthnh,corrlengthtr,corrlengthsh
real(r_single),public ::  obtimelnh,obtimeltr,obtimelsh
real(r_single),public ::  zhuberleft,zhuberright
real(r_single),public ::  lnsigcutoffnh,lnsigcutofftr,lnsigcutoffsh,&
               lnsigcutoffsatnh,lnsigcutoffsattr,lnsigcutoffsatsh,&
               lnsigcutoffpsnh,lnsigcutoffpstr,lnsigcutoffpssh
real(r_single),public :: analpertwtnh,analpertwtsh,analpertwttr,sprd_tol,saterrfact
real(r_single),public ::  paoverpb_thresh,latbound,delat,p5delat,delatinv
real(r_single),public ::  latboundpp,latboundpm,latboundmp,latboundmm
real(r_single),public :: covl_minfact, covl_efold
! if npefiles=0, diag files are read (concatenated pe* files written by gsi)
! if npefiles>0, npefiles+1 pe* files read directly
! the pe* files are assumed to be located in <obspath>/gsitmp_mem###
! (<obspath>/gsitmp_ensmean for ensemble mean).
integer,public :: npefiles = 0
! for LETKF, max number of obs in local volume.
! default is -1, which means take all obs within
! specified localization radius.  if nobsl_max > 0,
! only the first nobsl_max closest obs within the
! localization radius will be used. Ignored
! if letkf_flag = .false.
! If dfs_sort=T, DFS is used instead of distance
! for ob selection.
integer,public :: nobsl_max = -1
! for modulated ensemble, neigv is the number of
! eigenvectors of the vertical localization matrix
! if neigv=0, ob space localization is used
integer,public :: neigv = 0
real(r_double) :: vlocal_eval
real(r_double),public,dimension(:,:), allocatable :: vlocal_evecs
logical,public :: params_initialized = .true.
logical,public :: save_inflation = .false.
! do sat bias correction update.
logical,public :: lupd_satbiasc = .false.
! do ob space update with serial filter (only used if letkf_flag=.true.)
logical,public :: lupd_obspace_serial = .false.
! disable vertical localization for letkf
logical,public :: letkf_novlocal = .false.
! simple_partition=.false. does more sophisticated
! load balancing for ob space update.
logical,public :: simple_partition = .true.
logical,public :: reducedgrid = .false.
logical,public :: univaroz = .true.
logical,public :: regional = .false.
logical,public :: use_gfs_nemsio = .false.
logical,public :: arw = .false.
logical,public :: nmm = .true.
logical,public :: nmm_restart = .true.
logical,public :: nmmb = .false.
logical,public :: letkf_flag = .false.

! next two are no longer used, instead they are inferred from anavinfo
logical,public :: massbal_adjust = .false. 
integer(i_kind),public :: nvars = -1

! Use Sakov's 'deterministic EnKF' approx. (K/2 used for pert update)
logical,public :: denkf = .false.
! sort obs in LETKF in order of decreasing DFS
logical,public :: dfs_sort = .false.

! if true generate additional input files
! required for EFSO calculations
logical,public :: fso_cycling = .false.

! if true perform efso calculations
logical,public :: fso_calculate = .false.

! if true, use ensemble mean qsat in definition of
! normalized humidity analysis variable (instead of
! qsat for each member, which is the default behavior
! when pseudo_rh=.true.  If pseudo_rh=.false, use_qsatensmean
! is ignored.
logical,public :: use_qsatensmean = .false.
logical,public :: write_spread_diag = .false.
! if true, use jacobian from GSI stored in diag file to compute
! ensemble perturbations in observation space.
logical,public :: lobsdiag_forenkf = .false.
! if true, use netcdf diag files, otherwise use binary diags
logical,public :: netcdf_diag = .false.

namelist /nam_enkf/datestring,datapath,iassim_order,nvars,&
                   covinflatemax,covinflatemin,deterministic,sortinc,&
                   corrlengthnh,corrlengthtr,corrlengthsh,&
                   varqc,huber,nlons,nlats,smoothparm,use_qsatensmean,&
                   readin_localization, zhuberleft,zhuberright,&
                   obtimelnh,obtimeltr,obtimelsh,reducedgrid,&
                   lnsigcutoffnh,lnsigcutofftr,lnsigcutoffsh,&
                   lnsigcutoffsatnh,lnsigcutoffsattr,lnsigcutoffsatsh,&
                   lnsigcutoffpsnh,lnsigcutoffpstr,lnsigcutoffpssh,&
                   fgfileprefixes,anlfileprefixes,statefileprefixes,&
                   covl_minfact,covl_efold,lupd_obspace_serial,letkf_novlocal,&
                   analpertwtnh,analpertwtsh,analpertwttr,sprd_tol,&
                   nlevs,nanals,saterrfact,univaroz,regional,use_gfs_nemsio,&
                   paoverpb_thresh,latbound,delat,pseudo_rh,numiter,biasvar,&
                   lupd_satbiasc,cliptracers,simple_partition,adp_anglebc,angord,&
                   newpc4pred,nmmb,nhr_anal,nhr_state, fhr_assim,nbackgrounds,nstatefields, &
                   save_inflation,nobsl_max,lobsdiag_forenkf,netcdf_diag,&
                   letkf_flag,massbal_adjust,use_edges,emiss_bc,iseed_perturbed_obs,npefiles,&
                   neigv,denkf,dfs_sort,write_spread_diag,fso_cycling,fso_calculate,imp_physics,lupp

namelist /nam_wrf/arw,nmm,nmm_restart
namelist /satobs_enkf/sattypes_rad,dsis
namelist /ozobs_enkf/sattypes_oz


contains

subroutine read_namelist()
integer i,j,nb
logical fexist
! have all processes read namelist from file enkf.nml

! defaults
! time (analysis time YYYYMMDDHH)
datestring = "0000000000" ! if 0000000000 will not be used.
! corrlength (length for horizontal localization in km)
corrlengthnh = 2800
corrlengthtr = 2800
corrlengthsh = 2800
! read in localization length scales from an external file.
readin_localization = .false.
! min and max inflation.
covinflatemin = 1.0_r_single
covinflatemax = 1.e30_r_single
! lnsigcutoff (length for vertical localization in ln(p))
lnsigcutoffnh = 2._r_single
lnsigcutofftr = 2._r_single
lnsigcutoffsh = 2._r_single
lnsigcutoffsatnh = -999._r_single ! value for satellite radiances
lnsigcutoffsattr = -999._r_single ! value for satellite radiances
lnsigcutoffsatsh = -999._r_single ! value for satellite radiances
lnsigcutoffpsnh = -999._r_single  ! value for surface pressure
lnsigcutoffpstr = -999._r_single  ! value for surface pressure
lnsigcutoffpssh = -999._r_single  ! value for surface pressure
! ob time localization
obtimelnh = 1.e10
obtimeltr = 1.e10
obtimelsh = 1.e10
! min localization reduction factor for adaptive localization
! based on HPaHt/HPbHT. Default (1.0) means no adaptive localization.
! 0.25 means minimum localization is 0.25*corrlength(nh,tr,sh).
covl_minfact = 1.0
! efolding distance for adapative localization.
! Localization reduction factor is 1. - exp( -((1.-paoverpb)/covl_efold) )
! When 1-pavoerpb=1-HPaHt/HPbHt=cov_efold localization scales reduced by
! factor of 1-1/e ~ 0.632. When paoverpb==>1, localization scales go to zero.
! When paoverpb==>1, localization scales not reduced.
covl_efold = 1.e-10
! path to data directory
datapath = " " ! mandatory
! tolerance for background check.
! obs are not used if they are more than sqrt(S+R) from mean,
! where S is ensemble variance and R is observation error variance.
sprd_tol = 9.9e31_r_single
! definition of tropics and mid-latitudes (for inflation).
latbound = 25._r_single ! this is where the tropics start
delat = 10._r_single    ! width of transition zone.
! adaptive posterior inflation parameter.
analpertwtnh = 0.0_r_single ! no inflation (1 means inflate all the way back to prior spread)
analpertwtsh = 0.0_r_single
analpertwttr = 0.0_r_single
! if ob space posterior variance divided by prior variance
! less than this value, ob is skipped during serial processing.
paoverpb_thresh = 1.0_r_single! don't skip any obs
! set to to 0 for the order they are read in, 1 for random order, or 2 for
! order of predicted posterior variance reduction (based on prior)
iassim_order = 0
! use 'pseudo-rh' analysis variable, as in GSI.
pseudo_rh = .false.
! if deterministic is true, use LETKF/EnSRF w/o perturbed obs.
! if false, use perturbed obs EnKF/LETKF.
deterministic = .true.
! if deterministic is false, re-order obs to minimize regression erros
! as described in Anderson (2003) (only used for serial filter).
sortinc = .true.
! type of GFS microphyics.
! 99: Zhao-Carr, 11: GFDL
imp_physics = 99
! lupp, if true output extra variables
lupp = .false.
! these are all mandatory.
! nlons and nlats are # of lons and lats
nlons = 0
nlats = 0
! total number of levels
nlevs = 0
! number of ensemble members
nanals = 0
! background error variance for rad bias coeffs  (used in radbias.f90)
! default is (old) GSI value.
! if negative, bias coeff error variace is set to -biasvar/N, where
! N is number of obs per instrument/channel.
! if newpc4pred is .true., biasvar is not used - the estimated
! analysis error variance from the previous cycle is used instead
! (same as in the GSI).
biasvar = 0.1_r_single

! factor to multiply sat radiance errors.
saterrfact = 1._r_single
! number of times to iterate state/bias correction update.
! (numiter = 1 means no iteration, but update done in both observation and model
! space)
! (for LETKF, numiter = 0 shuts off update in observation space)
numiter = 1

! varqc parameters
varqc = .false.
huber = .false. ! use huber norm instead of "flat-tail"
zhuberleft=1.e30_r_single
zhuberright=1.e30_r_single
! smoothing paramater for inflation (-1 for no smoothing)
smoothparm = -1
! if true, tracers are clipped to zero when read in, and just
! before they are written out.
cliptracers = .true.

! Initialize satellite files to ' '
sattypes_rad=' '
sattypes_oz=' '
dsis=' '

! Initialize first-guess and analysis file name prefixes.
! (blank means use default names)
fgfileprefixes = ''; anlfileprefixes=''; statefileprefixes=''

! read from namelist file, doesn't seem to work from stdin with mpich
open(912,file='enkf.nml',form="formatted")
read(912,nam_enkf)
read(912,satobs_enkf)
read(912,ozobs_enkf)
if (regional) then
  read(912,nam_wrf)
endif
close(912)

! find number of satellite files
nsats_rad=0
do i=1,nsatmax_rad
  if(sattypes_rad(i) == ' ') cycle
  nsats_rad=nsats_rad+1
end do
if(nproc == 0)write(6,*) 'number of satellite radiance files used',nsats_rad

! find number of satellite files
nsats_oz=0
do i=1,nsatmax_oz
  if(sattypes_oz(i) == ' ') cycle
  nsats_oz=nsats_oz+1
end do
if(nproc == 0)write(6,*) 'number of satellite ozone files used',nsats_oz


! default value of vertical localization for sat radiances
! and surface pressure should be same as other data.
if (lnsigcutoffsatnh < 0._r_single) lnsigcutoffsatnh = lnsigcutoffnh
if (lnsigcutoffsattr < 0._r_single) lnsigcutoffsattr = lnsigcutofftr
if (lnsigcutoffsatsh < 0._r_single) lnsigcutoffsatsh = lnsigcutoffsh
if (lnsigcutoffpsnh < 0._r_single) lnsigcutoffpsnh = lnsigcutoffnh
if (lnsigcutoffpstr < 0._r_single) lnsigcutoffpstr = lnsigcutofftr
if (lnsigcutoffpssh < 0._r_single) lnsigcutoffpssh = lnsigcutoffsh
p5delat=0.5_r_single*delat
latboundpp=latbound+p5delat
latboundpm=latbound-p5delat
latboundmp=-latbound+p5delat
latboundmm=-latbound-p5delat
delatinv=1.0_r_single/delat

! if neigv > 0, use modulated ensemble to compute Kalman gain (but use
! this K to update only original ensemble). Only works with LETKF/DENKF.
allocate(vlocal_evecs(neigv,nlevs+1))
if (neigv > 0) then
  if (.not. lobsdiag_forenkf) then
    if (nproc .eq. 0) then
       print *,'lobsdiag_forenkf must be true if neigv>0'
    endif
    call stop2(19)
  endif
  ! neigv>0 implies letkf_flag=denkf=letkf_novlocal=lobsdiag_forenkf=.true. and
  ! lnsigcutoff* = 1.e30
  !if (.not. letkf_flag) then
  !  if (nproc .eq. 0) print *,"re-setting letkf_flag to true"
  !  letkf_flag = .true.
  !endif
  if (letkf_flag .and. .not. letkf_novlocal) then
     if (nproc .eq. 0) print *,"re-setting letkf_novlocal to true"
     letkf_novlocal = .true.
  endif
  if (letkf_flag .and. letkf_novlocal .and. .not. denkf) then
     if (nproc .eq. 0) print *,"re-setting denkf to true"
     denkf = .true.
  endif
  ! set vertical localization parameters to very large values
  ! (turns vertical localization off)
  lnsigcutoffnh = 1.e30
  lnsigcutoffsh = 1.e30
  lnsigcutofftr = 1.e30
  lnsigcutoffsatnh = 1.e30
  lnsigcutoffsatsh = 1.e30
  lnsigcutoffsattr = 1.e30
  lnsigcutoffpsnh = 1.e30
  lnsigcutoffpssh = 1.e30
  lnsigcutoffpstr = 1.e30
! read in eigenvalues/vectors of vertical localization matrix on all tasks
! (text file vlocal_eig.dat must exist)
  inquire(file='vlocal_eig.dat',exist=fexist)
  if ( fexist ) then
     open(7,file='vlocal_eig.dat',status="old",action="read")
  else
     if (nproc .eq. 0) print *, 'error vlocal_eig.dat does not exist'
     call stop2(19)
  endif
  if (nproc .eq. 0) print *,'vertical localization eigenvalues'
  do i = 1,neigv
     read(7,*) vlocal_eval
     if (nproc .eq. 0) print *,i,vlocal_eval
     do j = 1,nlevs
        read(7,*) vlocal_evecs(i,j)
     enddo
     ! nlevs+1 same as level 1 (2d variables treated as surface)
     vlocal_evecs(i,nlevs+1) = vlocal_evecs(i,1)
  enddo
  close(7)
endif

! have to do ob space update for serial filter (not for LETKF).
if ((.not. letkf_flag .or. lupd_obspace_serial) .and. numiter < 1) numiter = 1

if (nproc == 0) then

   print *,'namelist parameters:'
   print *,'--------------------'
   write(6,nam_enkf)
   print *,'--------------------'

! check for mandatory namelist variables

   if (nlons == 0 .or. nlats == 0 .or. nlevs == 0 .or. nanals == 0) then
      print *,'must specify nlons,nlats,nlevs,nanals in namelist'
      print *,nlons,nlats,nlevs,nanals
      call stop2(19)
   end if
   if (numproc .lt. nanals) then
      print *,'total number of mpi tasks must be >= nanals'
      print *,'tasks, nanals = ',numproc,nanals
      call stop2(19)
   endif
   if (datapath == ' ') then
      print *,'need to specify datapath in namelist!'
      call stop2(19)
   end if
   if(regional .and. .not. arw .and. .not. nmm .and. .not. nmmb) then
      print *, 'must select either arw, nmm or nmmb regional dynamical core'
      call stop2(19)
   endif
   if (letkf_flag .and. univaroz) then
     print *,'univaroz is not supported in LETKF!'
     call stop2(19)
   end if
   if ((obtimelnh < 1.e10 .or. obtimeltr < 1.e10 .or. obtimelsh < 1.e10) .and. &
       letkf_flag) then
     print *,'warning: no time localization in LETKF!'
   endif

   print *, trim(adjustl(datapath))
   if (datestring .ne. '0000000000') print *, 'analysis time ',datestring
   if (neigv > 0) then
      print *,nanals,' (unmodulated) members'
      print *,neigv,' eigenvectors for vertical localization'
      print *,nanals*neigv,' modulated ensemble members'
   else
      print *,nanals,' members'
   endif

! check for deprecated namelist variables
   if (nvars > 0 .or. massbal_adjust) then
      print *,'WARNING: nvars and massbal_adjust are no longer used!'
      print *,'They are inferred from the anavinfo file instead.'
   endif
   
end if

! background forecast time for analysis
nbackgrounds=0
do while (nhr_anal(nbackgrounds+1) > 0)
   write(charfhr_anal(nbackgrounds+1),'(i2.2)') nhr_anal(nbackgrounds+1)
   if (trim(fgfileprefixes(nbackgrounds+1)) .eq. "") then
     ! default first-guess file prefix
     if (regional) then
      if (nbackgrounds > 1) then
        fgfileprefixes(nbackgrounds+1)="firstguess_fhr"//charfhr_anal(nbackgrounds+1)//"."
      else
        fgfileprefixes(nbackgrounds+1)="firstguess."
      endif
     else  ! global
      fgfileprefixes(nbackgrounds+1)="sfg_"//datestring//"_fhr"//charfhr_anal(nbackgrounds+1)//"_"
     endif
   endif
   nbackgrounds = nbackgrounds+1
end do

! state fields
nstatefields=0
do while (nhr_state(nstatefields+1) > 0)
   write(charfhr_state(nstatefields+1),'(i2.2)') nhr_state(nstatefields+1)
   if (trim(statefileprefixes(nstatefields+1)) .eq. "") then
     ! default first-guess file prefix
     if (regional) then
      if (nstatefields > 1) then
        statefileprefixes(nstatefields+1)="firstguess_fhr"//charfhr_state(nstatefields+1)//"."
      else
        statefileprefixes(nstatefields+1)="firstguess."
      endif
     else  ! global
      statefileprefixes(nstatefields+1)="sfg_"//datestring//"_fhr"//charfhr_state(nstatefields+1)//"_"
     endif
   endif
   nstatefields = nstatefields+1
end do

do nb=1,nbackgrounds
   if (trim(anlfileprefixes(nb)) .eq. "") then
     ! default analysis file prefix
     if (regional) then
      if (nbackgrounds > 1) then
        anlfileprefixes(nb)="analysis_fhr"//charfhr_anal(nb)//"."
      else
        anlfileprefixes(nb)="analysis."
      endif
     else ! global
!      if (nbackgrounds > 1) then
        anlfileprefixes(nb)="sanl_"//datestring//"_fhr"//charfhr_anal(nb)//"_"
!      else
!        anlfileprefixes(nb)="sanl_"//datestring//"_"
!      endif
     endif
   endif
enddo

if (nproc .eq. 0) then
  print *,'number of background forecast times to be used for H(x) = ',nstatefields
  print *,'first-guess forecast hours for observation operator = ',&
  charfhr_state(1:nstatefields)
endif

if (nproc .eq. 0) then
  print *,'number of background forecast times to be updated = ',nbackgrounds
  print *,'first-guess forecast hours for analysis = ',&
  charfhr_anal(1:nbackgrounds)
endif

call init_constants(.false.) ! initialize constants.
call init_constants_derived()

if (nproc == 0) then
    if (analpertwtnh > 0) then
       print *,'using multiplicative inflation based on Pa/Pb'
    else if (analpertwtnh < 0) then
       print *,'using relaxation-to-prior inflation'
    else
       print *,'no inflation'
    endif
end if

! rescale covariance localization length
corrlengthnh = corrlengthnh * 1.e3_r_single/rearth
corrlengthtr = corrlengthtr * 1.e3_r_single/rearth
corrlengthsh = corrlengthsh * 1.e3_r_single/rearth

! this var is .false. until this routine is called.
params_initialized = .true.

! reset lupd_obspace_serial to false if letkf not requested.
if (.not. letkf_flag .and. lupd_obspace_serial) then
  lupd_obspace_serial = .false.
  if (nproc == 0) then
   print *,'setting lupd_obspace_serial to .false., since letkf_flag is .false.'
  endif
endif

! set lupd_obspace_serial to .true. if letkf_flag is true
! and numiter > 0.
if (letkf_flag .and. .not. lupd_obspace_serial .and. numiter > 0) then
  lupd_obspace_serial = .true.
  if (nproc == 0) then
   print *,'setting lupd_obspace_serial to .true., since letkf_flag is .true. and numiter > 0'
  endif
endif

if (datapath(len_trim(datapath):len_trim(datapath)) .ne. '/') then
   ! add trailing slash if needed
   if (nproc .eq. 0) print *,'adding trailing slash to datapath..'
   datapath = trim(datapath)//'/'
endif

end subroutine read_namelist

end module params
