module convb_q
!$$$   module documentation block
!                .      .    .                                       .
! module:    convb_q
!   prgmmr: su          org: np2                date: 2014-03-28
! abstract:  This module contains variables and routines related
!            to the assimilation of conventional non linear qc 
!
! program history log:
!   2014-03-28  su  - original code - move reading observation non linear qc table 
!                                     from read_prepbufr to here so all the 
!                                     processor can have the new  information 
!
! Subroutines Included:
!   sub convb_q_read      - allocate arrays for and read in conventional b table 
!   sub convb_q_destroy   - destroy conventional b arrays
!
! Variable Definitions:
!   def btabl_q             -  the array to hold the b table
!   def bptabl_q             -  the array to have vertical pressure values
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$ end documentation block

use kinds, only:r_kind,i_kind,r_single
use constants, only: zero
use obsmod, only : bflag 
implicit none

! set default as private
  private
! set subroutines as public
  public :: convb_q_read
  public :: convb_q_destroy
! set passed variables as public
  public :: btabl_q,bptabl_q

  integer(i_kind),save:: ibtabl_q,itypex,itypey,lcount,iflag,k,m
  real(r_single),save,allocatable,dimension(:,:,:) :: btabl_q
  real(r_kind),save,allocatable,dimension(:)  :: bptabl_q

contains


  subroutine convb_q_read(mype)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    convinfo_err      read conventional information file
!
!     prgmmr:    su    org: np2                date: 2007-03-15
!
! abstract:  This routine reads the conventional error table file
!
! program history log:
!   2008-06-04  safford -- add subprogram doc block
!   2013-05-14  guo     -- add status and iostat in open, to correctly
!                          handle the error case of "obs error table not
!                          available to 3dvar".
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language:  f90
!   machine:   ibm RS/6000 SP
!
!$$$ end documentation block
     use constants, only: half
     implicit none

     integer(i_kind),intent(in   ) :: mype

     integer(i_kind):: ier

     allocate(btabl_q(100,33,6))

     btabl_q=1.e9_r_kind
      
     ibtabl_q=19
     open(ibtabl_q,file='btable_q',form='formatted',status='old',iostat=ier)
     if(ier/=0) then
        write(6,*)'CONVB_Q:  ***WARNING*** obs b table ("btable") not available to 3dvar.'
        lcount=0
        bflag=.false.
        return
     endif

     rewind ibtabl_q
     btabl_q=1.e9_r_kind
     lcount=0
     loopd : do 
        read(ibtabl_q,100,IOSTAT=iflag,end=120) itypey
        if( iflag /= 0 ) exit loopd
100     format(1x,i3,2x,i3)
        lcount=lcount+1
        itypex=itypey-99
        do k=1,33
           read(ibtabl_q,110)(btabl_q(itypex,k,m),m=1,6)
110        format(1x,6e12.5)
        end do
     end do   loopd
120  continue

     if(lcount<=0 .and. mype==0) then
        write(6,*)'CONVB_Q:  ***WARNING*** obs b table not available to 3dvar.'
        bflag=.false.
     else
        if(mype == 0) write(6,*)'CONVB_Q:  using observation b from user provided table'
        allocate(bptabl_q(34))
        bptabl_q=zero
        bptabl_q(1)=btabl_q(20,1,1)
        do k=2,33
           bptabl_q(k)=half*(btabl_q(20,k-1,1)+btabl_q(20,k,1))
        enddo
        bptabl_q(34)=btabl_q(20,33,1)
     endif

     close(ibtabl_q)

     return
  end subroutine convb_q_read


subroutine convb_q_destroy
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    convb_q_destroy      destroy conventional information file
!     prgmmr:    su    org: np2                date: 2014-0328-
!
! abstract:  This routine destroys arrays from convb_q file
!
! program history log:
!   2007-03-15  su 
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
     implicit none

     deallocate(btabl_q,bptabl_q)
     return
  end subroutine convb_q_destroy

end module convb_q



