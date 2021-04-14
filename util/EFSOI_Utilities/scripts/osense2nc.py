from netCDF4 import Dataset    # Note: python is case-sensitive!
import netCDF4 as nc
import numpy as np
import osense

#satnum_in = 100
strlen=20
osensefile='/scratch1/NCEPDEV/stmp4/Andrew.Eichmann/testtest/osense/osense_2019111918_final.dat'

(convdata, satdata, idate )= osense.read_osense( osensefile)

satnum_in = satdata.shape[0] 

columns1 =  [ 'obfit_prior',
                 'obsprd_prior',
                 'ensmean_obnobc',
                 'ensmean_ob',
                 'ob',
                 'oberrvar',
                 'lon',
                 'lat',
                 'pres',
                 'time',
                 'oberrvar_orig',
#                 'stattype',
#                 'obtype',
#                 'indxsat',
                 'osense_kin',
                 'osense_dry',
                 'osense_moist' ]


columns = [ ( 'obfit_prior' , 'Observation fit to the first guess'),
	( 'obsprd_prior' , 'Spread of observation prior'),
	( 'ensmean_obnobc' , 'Ensemble mean first guess (no bias correction)'),
	( 'ensmean_ob' , 'Ensemble mean first guess (bias corrected)'),
	( 'ob' , 'Observation value'),
	( 'oberrvar' , 'Observation error variance'),
	( 'lon' , 'Longitude'),
	( 'lat' , 'Latitude'),
	( 'pres' , 'Pressure'),
	( 'time' , 'Observation time'),
	( 'oberrvar_orig' , 'Original error variance'),
	( 'osense_kin' , 'Observation sensitivity (kinetic energy) [J/kg]'),
	( 'osense_dry' , 'Observation sensitivity (Dry total energy) [J/kg]'),
	( 'osense_moist' , 'Observation sensitivity (Moist total energy) [J/kg]') ]

try: ncfile.close()  # just to be safe, make sure dataset is not already open.
except: pass
#ncfile = Dataset('new.nc',mode='w',format='NETCDF4_CLASSIC') 
ncfile = Dataset('new.nc',mode='w',format='NETCDF4') 

ncfile.title='My satellite osense data'

satnum_dim = ncfile.createDimension('satnum', satnum_in) 
_ = ncfile.createDimension('nchars',strlen)

for dim in ncfile.dimensions.items():
    print(dim)

satnum = ncfile.createVariable('satnum', np.int32, ('satnum',))
satnum.long_name = 'number of satellite observations'
satnum[:] = list(range(1,satnum_in+1))

#obtype = ncfile.createVariable('obtype', np.str, ('satnum'))
obtype = ncfile.createVariable('obtype', 'S1', ('satnum','nchars'))
#obtype[:] = satdata[ 'obtype' ].to_numpy()
obtypestr=np.array(satdata[ 'obtype' ],dtype='S20')    
obtype[:] = nc.stringtochar(obtypestr )   
obtype.long_name = 'Observation element / Satellite name'


stattype = ncfile.createVariable('stattype', np.int32, ('satnum'))
stattype.long_name = 'Observation type'
stattype[:] = satdata[ 'stattype' ].to_numpy()

indxsat = ncfile.createVariable('indxsat', np.int32, ('satnum'))
indxsat.long_name = 'Satellite index (channel) set to zero'
indxsat[:] = satdata[ 'indxsat' ].to_numpy()



for column in columns:
    
    varname = column[0]
    ncvar = ncfile.createVariable(varname, np.float32, ('satnum'))
    ncvar.long_name = column[1]
    ncvar[:] = satdata[ varname ].to_numpy()






print(ncfile)
ncfile.close(); print('Dataset is closed!')


