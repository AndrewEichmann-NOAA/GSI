subroutine read_iasi(mype,val_iasi,ithin,rmesh,jsatid,gstime,&
     infile,lunout,obstype,nread,ndata,nodata,twind,sis,&
     mype_root,mype_sub,npe_sub,mpi_comm_sub,channelinfo)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    read_iasi                  read bufr format iasi data
! prgmmr :   tahara          org: np20                date: 2002-12-03
!
! abstract:  This routine reads BUFR format radiance 
!            files.  Optionally, the data are thinned to 
!            a specified resolution using simple quality control checks.
!
!            When running the gsi in regional mode, the code only
!            retains those observations that fall within the regional
!            domain
!
! program history log:
!   2002-12-03  tahara  - read aqua data in new bufr format
!   2004-05-28  kleist  - subroutine call update
!   2004-06-16  treadon - update documentation
!   2004-07-23  derber  - make changes to eliminate obs. earlier in thinning
!   2004-07-29  treadon - add only to module use, add intent in/out
!   2004-08-25  eliu    - added option to read separate bufr table
!   2004-10-15  derber  - increase weight given to surface channel check
!                         in AIRS data selection algorithm
!   2005-01-26  derber - land/sea determination and weighting for data selection
!   2005-07-07  derber - clean up code and improve selection criteria
!   2005-09-08  derber - modify to use input group time window
!   2005-09-28  derber - modify to produce consistent surface info
!   2005-10-17  treadon - add grid and earth relative obs location to output file
!   2005-10-18  treadon - remove array obs_load and call to sumload
!   2005-11-22  derber  - include mean in bias correction
!   2005-11-29  parrish - modify getsfc to work for different regional options
!   2006-02-01  parrish - remove getsfc (different version called now in read_obs)
!   2006-02-03  derber  - modify for new obs control and obs count
!   2006-03-07  derber - correct error in nodata count
!   2006-03-09  jung - correct sat zenith angle error (used before defined)
!   2006-04-21  keyser/treadon - modify ufbseq calls to account for change
!                                in NCEP bufr sequence for AIRS data
!   2006-05-19  eliu    - add logic to reset relative weight when all channels not used
!   2006-07-28  derber - modify reads so ufbseq not necessary
!                      - add solar and satellite azimuth angles remove isflg from output
!   2006-08-25  treadon - replace serial bufr i/o with parallel bufr i/o (mpi_io)
!
!   input argument list:
!     mype     - mpi task id
!     val_iasi - weighting factor applied to super obs
!     ithin    - flag to thin data
!     rmesh    - thinning mesh size (km)
!     jsatid   - satellite to read
!     gstime   - analysis time in minutes from reference date
!     infile   - unit from which to read BUFR data
!     lunout   - unit to which to write data for further processing
!     obstype  - observation type to process
!     twind    - input group time window (hours)
!     sis      - sensor/instrument/satellite indicator
!     mype_root - "root" task for sub-communicator
!     mype_sub - mpi task id within sub-communicator
!     npe_sub  - number of data read tasks
!     mpi_comm_sub - sub-communicator for data read
!
!   output argument list:
!     nread    - number of BUFR IASI observations read
!     ndata    - number of BUFR IASI profiles retained for further processing
!     nodata   - number of BUFR IASI observations retained for further processing
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
! Use modules
  use kinds, only: r_kind,r_double,i_kind
  use satthin, only: super_val,itxmax,makegrids,map2tgrid,destroygrids, &
               finalcheck,checkob
  use radinfo, only:n_sensors,iuse_rad,nusis,jpch_rad
  use crtm_channelinfo_define, only: crtm_channelinfo_type
  use crtm_planck_functions, only: crtm_planck_temperature,crtm_planck_radiance
  use gridmod, only: diagnostic_reg,regional,nlat,nlon,&
       tll2xy,txy2ll,rlats,rlons
  use constants, only: zero,deg2rad,one,three,izero,ione,rad2deg
!  use obsmod, only: iadate
  use mpi_bufr_mod, only: mpi_openbf,mpi_closbf,nblocks,mpi_nextblock,&
       mpi_readmg,mpi_ireadsb,mpi_ufbint,mpi_ufbrep

  implicit none


! Number of channels for sensors in BUFR
  integer(i_kind),parameter :: nchanl = 616		!--- 616 subset ch out of 8078 ch for AIRS
  integer(i_kind),parameter :: n_totchan  = 616 
  integer(i_kind),parameter :: maxinfo    =  33


! BUFR format for IASISPOT 
! Input variables
  integer(i_kind)  ,intent(in) :: mype
  integer(i_kind)  ,intent(in) :: ithin
  integer(i_kind)  ,intent(in) :: lunout
  integer(i_kind)  ,intent(in) :: mype_root
  integer(i_kind)  ,intent(in) :: mype_sub
  integer(i_kind)  ,intent(in) :: npe_sub
  integer(i_kind)  ,intent(in) :: mpi_comm_sub  
  character(len=10),intent(in) :: jsatid
  character(len=10),intent(in) :: infile
  character(len=10),intent(in) :: obstype
  character(len=20),intent(in) :: sis
  real(r_kind)     ,intent(in) :: twind
  real(r_kind)     ,intent(inout):: val_iasi
  real(r_kind)     ,intent(in) :: gstime
  real(r_kind)     ,intent(in) :: rmesh
  

! Output variables
  integer(i_kind),intent(inout) :: nread
  integer(i_kind)  ,intent(out) :: ndata,nodata
  

! BUFR file sequencial number
!  character(len=512)  :: table_file
  integer(i_kind)     :: lnbufr = 10

! Variables for BUFR IO    
  real(r_double),dimension(5)  :: linele
  real(r_double),dimension(13) :: allspot
  real(r_double),dimension(2,n_totchan) :: allchan
  real(r_double),dimension(3,10):: cscale
  real(r_double),dimension(6):: cloud_frac
  
  real(r_kind)      :: step, start,step_adjust
  character(len=8)  :: subset
  character(len=4)  :: senname
  character(len=80) :: allspotlist
  integer(i_kind)   :: nchanlr
  integer(i_kind)   :: iret


! Work variables for time
  integer(i_kind)   :: idate
  integer(i_kind)   :: idate5(5)
  character(len=10) :: date
  real(r_kind)      :: sstime, tdiff
  integer(i_kind)   :: nmind
  integer(i_kind)   :: iy, im, idd, ihh


! Other work variables
  real(r_kind)     :: clr_amt,piece,ten
  real(r_kind)     :: dlon, dlat
  real(r_kind)     :: dlon_earth,dlat_earth
  real(r_kind)     :: lza, lzaest,sat_height,sat_height_ratio
  real(r_kind)     :: timedif, pred, crit1, dist1
  real(r_kind)     :: sat_zenang, sol_zenang, sat_aziang, sol_aziang
  real(r_kind)     :: radiance, temperature
  real(r_kind)     :: tsavg,vty,vfr,sty,stp,sm,sn,zz,ff10,sfcr
  real(r_kind),dimension(0:4) :: rlndsea
  real(r_kind),dimension(0:3) :: sfcpct
  real(r_kind),dimension(0:3) :: ts
  real(r_kind),dimension(10) :: sscale
  real(r_kind),allocatable,dimension(:,:):: data_all
  real(r_kind),allocatable,dimension(:):: data_crit
  real(r_kind) disterr,disterrmax,rlon00,rlat00,r01

  logical          :: outside,iuse,assim
  logical          :: iasi

  integer(i_kind)  :: ifov, iscn, ioff, ilat, ilon, sensorindex
  integer(i_kind)  :: i, l, ll, iskip, ifovn
  integer(i_kind)  :: nreal, ichsst, ichansst, isflg,ioffset
  integer(i_kind)  :: itx, k, nele, itt, iout,n
  integer(i_kind),allocatable,dimension(:):: idata_itx
  integer(i_kind):: iexponent
  integer(i_kind):: mmblocks
  integer(i_kind):: isubset,idomsfc
  integer(i_kind):: ntest

  type(crtm_channelinfo_type),dimension(n_sensors) :: channelinfo

! Set standard parameters
  real(r_kind),parameter:: R60    =  60._r_kind
  real(r_kind),parameter:: R90    =  90._r_kind
  real(r_kind),parameter:: R360   = 360._r_kind
  real(r_kind),parameter:: d1     = 0.754_r_kind
  real(r_kind),parameter:: d2     = -2.265_r_kind
  real(r_kind),parameter:: tbmin  = 50._r_kind
  real(r_kind),parameter:: tbmax  = 550._r_kind
  real(r_kind),parameter:: earth_radius = 6371000._r_kind

! Initialize variables
  disterrmax=zero
  ntest=0
  nreal  = maxinfo
  ndata = 0
  nodata = 0
  iasi=      obstype == 'iasi'
  r01=0.01_r_kind
  ten=10.0_r_kind

  ilon=3
  ilat=4

!  write(6,*)'READ_IASI: mype, mype_root,mype_sub, npe_sub,mpi_comm_sub', &
!          mype, mype_root,mype_sub,mpi_comm_sub
     step   = 3.334_r_kind 
     start = -48.33_r_kind 
     step_adjust = 0.625_r_kind
     senname = 'IASI'
     nchanlr = nchanl
     ioffset=0
     rlndsea(0) = zero                       
     rlndsea(1) = 10._r_kind
     rlndsea(2) = 15._r_kind
     rlndsea(3) = 10._r_kind
     rlndsea(4) = 30._r_kind
!     if (mype_sub==mype_root) &
!          write(6,*)'READ_IASI:  iasi offset ',ioff,ichansst,ichsst
  
  allspotlist= &
   'SIID YEAR MNTH DAYS HOUR MINU SECO CLATH CLONH SAZA BEARAZ SOZA SOLAZI'
  
!  find IASI sensorindex  
   sensorindex = 0
   do i=1,n_sensors
!   CRTM rev1859 changes component name "sensorid" to "sensor_id"
!!  if ( channelinfo(i)%sensor_id == 'iasi616_metop-a' ) then

!   Use this line for CRTM rev899
    if ( channelinfo(i)%sensorid == 'iasi616_metop-a' ) then
       sensorindex = i
       exit
    endif
   end do 
   if (sensorindex == 0 ) write(6,*)'READ_IASI: sensorindex not set'

! If all channels of a given sensor are set to monitor or not
! assimilate mode (iuse_rad<1), reset relative weight to zero.
! We do not want such observations affecting the relative
! weighting between observations within a given thinning group.

  assim=.false.
  search: do i=1,jpch_rad
     if ((nusis(i)==sis) .and. (iuse_rad(i)>0)) then
        assim=.true.
        exit search
     endif
  end do search
  if (.not.assim) val_iasi=zero

! Make thinning grids
  call makegrids(rmesh)

! Open BUFR file
  open(lnbufr,file=infile,form='unformatted')

! Open BUFR table
  call openbf(lnbufr,'IN',lnbufr)
  call datelen(10)

! Read header
  call readmg(lnbufr,subset,idate,iret)
  call closbf(lnbufr)
  close(lnbufr)
  if( iret /= 0 ) return     ! no data?

  write(date,'( i10)') idate
  read(date,'(i4,3i2)') iy,im,idd,ihh
  if (mype_sub==mype_root) &
       write(6,*) 'READ_IASI:     bufr file date is ',iy,im,idd,ihh
  
! Allocate arrays to hold data
  nele=nreal+nchanl
  allocate(data_all(nele,itxmax),data_crit(itxmax),idata_itx(itxmax))

! Open up bufr file for mpi-io access
  call mpi_openbf(infile,npe_sub,mype_sub,mpi_comm_sub)
  
! Big loop to read data file
  mpi_loop: do mmblocks=0,nblocks-1,npe_sub
     if(mmblocks+mype_sub.gt.nblocks-1) then
        exit
     endif
     call mpi_nextblock(mmblocks+mype_sub)
     block_loop: do
        call mpi_readmg(lnbufr,subset,idate,iret)
        if (iret /=0) exit
        read(subset,'(2x,i6)')isubset
        read_loop: do while (mpi_ireadsb(lnbufr)==0)

!    Read IASI FOV information
     call mpi_ufbint(lnbufr,linele,5,1,iret,'FOVN SLNM QGFQ MJFC SELV')
     if ( linele(3) /= 0.0) cycle read_loop  ! problem with profile (QGFQ)

     call mpi_ufbint(lnbufr,allspot,13,1,iret,allspotlist)
     if(iret /= 1) cycle read_loop

!    Check observing position
     dlat_earth = allspot(8)   ! latitude
     dlon_earth = allspot(9)   ! longitude
     if( abs(dlat_earth) > R90  .or. abs(dlon_earth) > R360 .or. &
        (abs(dlat_earth) == R90 .and. dlon_earth /= ZERO) )then
       write(6,*)'READ_IASI:  ### ERROR IN READING ', senname, ' BUFR DATA:', &
            ' STRANGE OBS POINT (LAT,LON):', dlat_earth, dlon_earth
        cycle read_loop
     endif

!    Retrieve observing position
     if(dlon_earth >= R360)then
        dlon_earth = dlon_earth - R360
     else if(dlon_earth < ZERO)then
        dlon_earth = dlon_earth + R360
     endif

     dlat_earth = dlat_earth * deg2rad
     dlon_earth = dlon_earth * deg2rad

!    If regional, map obs lat,lon to rotated grid.
     if(regional)then

!    Convert to rotated coordinate.  dlon centered on 180 (pi),
!    so always positive for limited area
        call tll2xy(dlon_earth,dlat_earth,dlon,dlat,outside)
        if(diagnostic_reg) then
           call txy2ll(dlon,dlat,rlon00,rlat00)
           ntest=ntest+1
           disterr=acosd(sin(dlat_earth)*sin(rlat00)+cos(dlat_earth)*cos(rlat00)* &
                (sin(dlon_earth)*sin(rlon00)+cos(dlon_earth)*cos(rlon00)))
           disterrmax=max(disterrmax,disterr)
        end if

!    Check to see if in domain.  outside=.true. if dlon_earth,
!    dlat_earth outside domain, =.false. if inside
        if(outside) cycle read_loop

!    Global case 
     else
        dlat = dlat_earth
        dlon = dlon_earth
        call grdcrd(dlat,1,rlats,nlat,1)
        call grdcrd(dlon,1,rlons,nlon,1)
     endif

!    Check obs time
     idate5(1) = nint(allspot(2)) ! year
     idate5(2) = nint(allspot(3)) ! month
     idate5(3) = nint(allspot(4)) ! day
     idate5(4) = nint(allspot(5)) ! hour
     idate5(5) = nint(allspot(6)) ! minute

     if( idate5(1) < 1900 .or. idate5(1) > 3000 .or. &
         idate5(2) <    1 .or. idate5(2) >   12 .or. &
         idate5(3) <    1 .or. idate5(3) >   31 .or. &
         idate5(4) <    0 .or. idate5(4) >   24 .or. &
         idate5(5) <    0 .or. idate5(5) >   60 )then

         write(6,*)'READ_IASI:  ### ERROR IN READING ', senname, ' BUFR DATA:', &
             ' STRANGE OBS TIME (YMDHM):', idate5(1:5)
         cycle read_loop

     endif

!    Retrieve obs time
     call w3fs21(idate5,nmind)
     sstime = float(nmind) + allspot(7)/R60 ! add in seconds
     tdiff  = (sstime - gstime)/R60
     if (abs(tdiff)>twind) then
       write(6,*)'READ_IASI:  ### ERROR IN READING ', senname, ' BUFR DATA:', &
           ' OUTSIDE OBS WINDOW ', tdiff, '(ins seconds)'
       cycle read_loop
     endif
     
!    Observational info
     sat_zenang  = allspot(10) * deg2rad  ! satellite zenith angle
     sat_aziang  = allspot(11)            ! satellite azimuth angle
     sol_zenang = allspot(12)             ! solar zenith angle
     sol_aziang = allspot(13)             ! solar azimuth angle
     ifov = nint(linele(1))               ! field of view
     iscn = nint(linele(2))               ! scan line
     sat_height = linele(5)               ! satellite orbit height
     if ( ifov <= 60 ) sat_zenang = -sat_zenang

!    IASI fov ranges from 1 to 120.   Current angle dependent bias
!    correction has a maximum of 90 scan positions.   Geometry
!    of IASI scan allows us to remap 1-120 to 1-60.   Variable
!    ifovn below contains the remapped IASI fov.  This value is
!    passed on to and used in setuprad
     ifovn = (ifov-1)/2 + 1

!    Check field of view (FOVN) and satellite zenith angle (SAZA)
     if( ifov <    izero .or. ifov > 120 .or. abs(allspot(10)) > 360._r_kind ) then
        write(6,*)'READ_IASI:  ### ERROR IN READING ', senname, ' BUFR DATA:', &
             ' STRANGE OBS INFO(FOVN,SLNM,SAZA):', ifov, iscn, allspot(10)
        cycle read_loop
     endif

!    Compare IASI satellite scan angle and zenith angle
     piece = -step_adjust
     if ( mod(ifov,4) == 1 .or. mod(ifov,4) == 2 ) piece = step_adjust
     lza = ((start + float((ifov-1)/4)*step) + piece)*deg2rad
     sat_height_ratio = (earth_radius + sat_height)/earth_radius
     lzaest = asin(sat_height_ratio*sin(lza))
     if (abs(sat_zenang - lzaest)*rad2deg > 1.0) then
        write(6,*)' READ_IASI WARNING uncertainty in lza ', &
            lza*rad2deg,sat_zenang*rad2deg,sis,ifov,start,step
        cycle read_loop
     endif

!   Increment nread counter by n_totchan
     nread = nread + n_totchan

!   Clear Amount  (percent clear)
     call mpi_ufbrep(lnbufr,cloud_frac,1,6,iret,'FCPH')
     clr_amt = cloud_frac(1)
     if ( clr_amt < zero .or. clr_amt > 100.0_r_kind ) clr_amt = zero
     
!    Compute "score" for observation.  All scores>=0.0.  Lowest score is "best"
     pred = 100.0 - clr_amt

     timedif = 6.0_r_kind*abs(tdiff)        ! range:  0 to 18
     crit1 = 0.01_r_kind+timedif + pred
     call map2tgrid(dlat_earth,dlon_earth,dist1,crit1,itx,ithin,itt,iuse)
     if(.not. iuse)cycle read_loop


!   "Score" observation.  We use this information to identify "best" obs
!    Locate the observation on the analysis grid.  Get sst and land/sea/ice
!    mask.  
!     isflg    - surface flag
!                0 sea
!                1 land
!                2 sea ice
!                3 snow
!                4 mixed 
!      sfcpct(0:3)- percentage of 4 surface types
!                 (0) - sea percentage
!                 (1) - land percentage
!                 (2) - sea ice percentage
!                 (3) - snow percentage

     call deter_sfc(dlat,dlon,dlat_earth,dlon_earth,tdiff,isflg,idomsfc,sfcpct,ts,tsavg, &
                vty,vfr,sty,stp,sm,sn,zz,ff10,sfcr,mype)
!    Set common predictor parameters

     crit1 = crit1 + rlndsea(isflg)
 
     call checkob(dist1,crit1,itx,iuse)
     if(.not. iuse)cycle read_loop

     call mpi_ufbrep(lnbufr,cscale,3,10,iret,'STCH ENCH CHSF')
     if(iret /= 10) cycle read_loop

! The scaling factors are as follows, cscale(1) is the start channel number,
!                                     cscale(2) is the end channel number,
!                                     cscale(3) is the exponent scaling factor
! In our case (616 channels) there are 10 groups of cscale (dimension :: cscale(3,10))
!  The units are W/m2..... you need to convert to mW/m2.... (subtract 5 from cscale(3)
     do i=1,10  ! convert exponent scale factor to int and change units
       iexponent = -(int(cscale(3,i)) - 5)
       sscale(i)=ten**iexponent
     end do

!    Read IASI channel number(CHNM) and radiance (SCRA)

     call mpi_ufbint(lnbufr,allchan,2,n_totchan,iret,'SCRA CHNM')
     if( iret /= n_totchan)then
        write(6,*)'READ_IASI:  ### ERROR IN READING ', senname, ' BUFR DATA:', &
             iret, ' CH DATA IS READ INSTEAD OF ',n_totchan
        cycle read_loop
     endif

     iskip = 0
     if ( sensorindex /= 0 ) then
     do i=1,n_totchan
!     check that channel number is within reason
      if (( allchan(1,i) > 0.0_r_kind .and. allchan(1,i) < 99999._r_kind) .and. &  ! radiance bounds
          (allchan(2,i) < 8462._r_kind .and. allchan(2,i) > 0.0_r_kind )) then      ! chan # bounds
!         radiance to BT calculation
          radiance = allchan(1,i)
          if( allchan(2,i) >= cscale(1,1) .and. allchan(2,i) <= cscale(2,1)) then
            radiance = allchan(1,i)*sscale(1)
          elseif ( allchan(2,i) >= cscale(1,2) .and. allchan(2,i) <= cscale(2,2)) then
            radiance = allchan(1,i)*sscale(2)
          elseif ( allchan(2,i) >= cscale(1,3) .and. allchan(2,i) <= cscale(2,3)) then
            radiance = allchan(1,i)*sscale(3)
          elseif ( allchan(2,i) >= cscale(1,4) .and. allchan(2,i) <= cscale(2,4)) then
            radiance = allchan(1,i)*sscale(4)
          elseif ( allchan(2,i) >= cscale(1,5) .and. allchan(2,i) <= cscale(2,5)) then
            radiance = allchan(1,i)*sscale(5)
          elseif ( allchan(2,i) >= cscale(1,6) .and. allchan(2,i) <= cscale(2,6)) then
            radiance = allchan(1,i)*sscale(6)
          elseif ( allchan(2,i) >= cscale(1,7) .and. allchan(2,i) <= cscale(2,7)) then
            radiance = allchan(1,i)*sscale(7)
          elseif ( allchan(2,i) >= cscale(1,8) .and. allchan(2,i) <= cscale(2,8)) then
            radiance = allchan(1,i)*sscale(8)
          elseif ( allchan(2,i) >= cscale(1,9) .and. allchan(2,i) <= cscale(2,9)) then
            radiance = allchan(1,i)*sscale(9)
          elseif ( allchan(2,i) >= cscale(1,10) .and. allchan(2,i) <= cscale(2,10)) then
            radiance = allchan(1,i)*sscale(10)
          endif

          call crtm_planck_temperature(sensorindex,i,radiance,temperature)
             allchan(1,i) = temperature
          if(temperature < tbmin .or. temperature > tbmax ) then
             allchan(1,i) = zero
             iskip = iskip + 1
             write(6,*)'READ_IASI:  skipped',i,temperature,allchan(2,1),allchan(2,i-1)
          endif
      else           ! error with channel number or radiance
!          write(6,*)'READ_IASI:  iasi chan error',i,allchan(1,i), allchan(2,i)
          allchan(1,i) = zero
          iskip = iskip + 1
      endif
     end do
     endif

     crit1=crit1 + 10.0_r_kind*float(iskip)
!     if( iskip >= 20 )cycle read_loop 


!    Map obs to grids
     call finalcheck(dist1,crit1,ndata,itx,iout,iuse,sis)
     if(.not. iuse)cycle read_loop

!   write(6,*)'READ_IASI: using the data',iout,dist1,crit1,ndata,sis
!JAJ
!     if (clr_amt >= 99 ) write(6,99)'clear', dlon_earth*rad2deg, dlat_earth*rad2deg, &
!          sol_zenang
!  99 format(1x,a6,f8.2,f7.2,4f8.2)

     data_all(1,iout) = 4                   ! satellite ID (temp. 49)
     data_all(2,iout) = tdiff               ! time diff (obs-anal) (hrs)
     data_all(3,iout) = dlon                ! grid relative longitude
     data_all(4,iout) = dlat                ! grid relative latitude
     data_all(5,iout) = sat_zenang          ! satellite zenith angle (rad)
     data_all(6,iout) = sat_aziang          ! satellite azimuth angle (deg)
     data_all(7,iout) = lza                 ! look angle (rad)
     data_all(8,iout) = ifovn               ! fov number
     data_all(9,iout) = sol_zenang          ! solar zenith angle (deg)
     data_all(10,iout)= sol_aziang          ! solar azimuth angle (deg)
     data_all(11,iout)= sfcpct(0)           ! ocean percentage
     data_all(12,iout)= sfcpct(1)           ! land percentage
     data_all(13,iout)= sfcpct(2)           ! ice percentage
     data_all(14,iout)= sfcpct(3)           ! snow percentage
!
     data_all(15,iout)= ts(0)               ! ocean skin temperature
     data_all(16,iout)= ts(1)               ! land skin temperature
     data_all(17,iout)= ts(2)               ! ice skin temperature
     data_all(18,iout)= ts(3)               ! snow skin temperature
     data_all(19,iout)= tsavg               ! average skin temperature
     data_all(20,iout)= vty                 ! vegetation type
     data_all(21,iout)= vfr                 ! vegetation fraction
     data_all(22,iout)= sty                 ! soil type
     data_all(23,iout)= stp                 ! soil temperature
     data_all(24,iout)= sm                  ! soil moisture
     data_all(25,iout)= sn                  ! snow depth
     data_all(26,iout)= zz                  ! surface height
     data_all(27,iout)= idomsfc + 0.001     ! dominate surface type
     data_all(28,iout)= sfcr                ! surface roughness
     data_all(29,iout)= ff10                ! ten meter wind factor

     data_all(30,iout)= dlon_earth*rad2deg  ! earth relative longitude (degrees)
     data_all(31,iout)= dlat_earth*rad2deg  ! earth relative latitude (degrees)

     data_all(32,iout)= val_iasi
     data_all(33,iout)= itt

     do l=1,nchanl
        data_all(l+nreal,iout) = allchan(1,l+ioffset)   ! brightness temerature
     end do

     idata_itx(iout) = itx                  ! thinning grid location
     data_crit(iout) = crit1*dist1          ! observation "score"

    enddo read_loop
 end do block_loop
end do mpi_loop

! If multiple tasks read input bufr file, allow each tasks to write out
! information it retained and then let single task merge files together

  if (npe_sub>1) &
       call combine_radobs(mype,mype_sub,mype_root,npe_sub,mpi_comm_sub,&
       nele,itxmax,nread,ndata,data_all,data_crit,idata_itx)


! Allow single task to check for bad obs, update superobs sum,
! and write out data to scratch file for further processing.
  if (mype_sub==mype_root) then

!    Identify "bad" observation (unreasonable brightness temperatures).
!    Update superobs sum according to observation location

     do n=1,ndata
        do i=1,nchanl
           if(data_all(i+nreal,n) > tbmin .and. &
                data_all(i+nreal,n) < tbmax)nodata=nodata+1
!             nodata = nodata + 1 ! added JAJ
        end do
        itt=nint(data_all(nreal,n))
        super_val(itt)=super_val(itt)+val_iasi
     end do

!    Write final set of "best" observations to output file
     write(lunout) obstype,sis,nreal,nchanl,ilat,ilon
     write(lunout) ((data_all(k,n),k=1,nele),n=1,ndata)
  
  endif

! Close bufr file
  call mpi_closbf
  call closbf(lnbufr)

! Deallocate data arrays
  deallocate(data_all,data_crit,idata_itx)


! Deallocate satthin arrays
1000 continue
  call destroygrids

  if(diagnostic_reg .and. ntest > 0 .and. mype_sub==mype_root) &
       write(6,*)'READ_IASI:  mype,ntest,disterrmax=',&
       mype,ntest,disterrmax
  
  return
end subroutine read_iasi
