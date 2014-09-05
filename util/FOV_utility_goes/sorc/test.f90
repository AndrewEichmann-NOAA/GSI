 program test

 use constants
 use calc_fov_geo

 implicit none

 character(len=8)  :: stnid

 integer :: i, j
 integer :: instr, ichan, ichan_tot
 integer :: nlev, nflag

 logical :: valid

 real(kind=4) :: tim
 real :: dlat, dlon
 real :: sublat, sublon
 real :: lat_mdl, lon_mdl
 real :: lat_fov, lon_fov
 real :: power
 real :: expansion
 real :: start_lat, start_lon
 real :: end_lat, end_lon
 real :: lats(npoly),lons(npoly)
 real, allocatable :: lats_edge_fov(:,:), lons_edge_fov(:,:)

 namelist /setup/ instr, sublat, sublon, lat_fov, lon_fov

 call init_constants_derived
 call init_constants(.false.)

 open (81, file="./config.nml")
 read (81, nml=setup)
 close(81)

 select case (instr)
   case (31)
     ichan_tot = 5
   case (32)
     ichan_tot = 19
   case default
     print*,'** ERROR. INVALID SATELLITE INSTRUMENT NUMBER: ', instr
     print*,'** STOP.'
     stop 11
 end select

 expansion = 1.0

 call instrument_init(instr, lat_fov, lon_fov, sublat, sublon, expansion, valid)

 if (.not. valid) then
   print*,'error in instrument_init'
   stop
 else
   print*,'init complete'
 end if

 allocate(lats_edge_fov(ichan_tot,npoly))
 allocate(lons_edge_fov(ichan_tot,npoly))

 open (65, file="./ellipse.dat", form="unformatted")
 stnid = "aaaaaaa"
 tim = 0.0
 nflag = 1

 do ichan = 1, ichan_tot

   call fov_ellipse_geo (ichan, lat_fov, lon_fov, lats, lons)

   lats_edge_fov(ichan,:)=lats
   lons_edge_fov(ichan,:)=lons

   nlev=1
   do i = 1, npoly
     write(65) stnid, real(lats_edge_fov(ichan,i),4), real(lons_edge_fov(ichan,i),4), tim, nlev, nflag
     write(65) real(0.0,4)
   enddo
   nlev=0
   write(65) stnid, real(lats_edge_fov(ichan,1),4), real(lons_edge_fov(ichan,1),4), tim, nlev, nflag

 enddo

 close(65)

 open (9, file="./power.dat", form="unformatted")
 stnid = "aaaaaaa"
 tim = 0.0
 nflag = 1

 CHANNEL : do ichan = 1, ichan_tot

   if (ichan_tot > 1) then
     print*,'- DETERMINE RETURNED POWER FOR CHANNEL ',ichan
   else
     print*,'- DETERMINE RETURNED POWER'
   endif

   start_lat=minval(lats_edge_fov(ichan,:))
   end_lat=maxval(lats_edge_fov(ichan,:))
   start_lon=minval(lons_edge_fov(ichan,:))
   end_lon=maxval(lons_edge_fov(ichan,:))

   dlat = (end_lat-start_lat) / 8.0
   dlon = (end_lon-start_lon) / 8.0

   lat_mdl = start_lat - (dlat * 2.0)
   do while (lat_mdl < (end_lat + (dlat*2.1)))
     lon_mdl = start_lon - (dlon * 2.0)
     do while (lon_mdl < (end_lon + (dlon*2.1)))

       call inside_fov_geo(instr,ichan, &
              lat_fov, lon_fov, lat_mdl, lon_mdl, expansion, power)

       if (power>=0.005) then
         nlev = 1
         write(9) stnid, real(lat_mdl,4), real(lon_mdl,4), tim, nlev, nflag
         write(9) real(power*100.,4)
       endif
       lon_mdl = lon_mdl + dlon
     enddo
     lat_mdl = lat_mdl + dlat
   enddo

! end of record marker for grads station file.
   nlev = 0
   write(9) stnid, real(lat_mdl,4), real(lon_mdl,4), tim, nlev, nflag
 enddo CHANNEL

 close (9)

 deallocate (lats_edge_fov, lons_edge_fov)

 stop
 end program test
