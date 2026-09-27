# Tract-level mislabel check

## 1. Checks

| | tracts with a station | invisible | invisible tracts holding a fire_department place (must be 0) |
|---|---|---|---|
| non-tribal | 2,723 | 577 | 0 |
| tribal | 513 | 163 | 0 |

Published: non-tribal 2,723 / 577, tribal 513 / 163.

## 2. Invisible tracts that hold the station under another label

| | invisible tracts | with a strict match | with any match (strict or loose) | still invisible (strict) | invisible rate before -> after (strict) |
|---|---|---|---|---|---|
| non-tribal | 577 | 218 (37.8%) | 246 (42.6%) | 359 | 21.2% -> **13.2%** |
| tribal | 163 | 64 (39.3%) | 69 (42.3%) | 99 | 31.8% -> **19.3%** |

All regions: 282 strict, 315 any, of 740 invisible tracts.

## 3. By region (strict)

| region | non-tribal: invisible -> still invisible | tribal: invisible -> still invisible |
|---|---|---|
| eastern-ok | 21.2% -> 14.4% (of 104) | 31.1% -> 18.3% (of 476) |
| maricopa-az | 20.4% -> 14.2% (of 402) | 41.7% -> 33.3% (of 24) |
| northern-ca | 27.9% -> 17.7% (of 265) | 38.5% -> 30.8% (of 13) |
| south-central-tx | 20.4% -> 12.3% (of 1952) | no tribal tracts |

## 4. What the mislabelled stations are filed as (strict, invisible tracts)

| primary category | non-tribal | tribal |
|---|---|---|
| fire_protection_service | 194 | 65 |
| central_government_office | 25 | 4 |
| community_services_non_profits | 10 | 4 |
| public_service_and_government | 6 | 3 |
| ambulance_and_ems_services | 6 | 1 |
| police_department | 2 | 4 |
| physical_therapy | 1 | 1 |
| None | 2 | 0 |
| health_and_medical | 2 | 0 |
| medical_service_organizations | 2 | 0 |
| professional_services | 2 | 0 |
| real_estate_service | 1 | 0 |
| beach | 1 | 0 |
| bar | 1 | 0 |
| hospital | 1 | 0 |

## 5. Upstream source of fire places, all tracts with a station

| source dataset | correctly tagged, non-tribal | correctly tagged, tribal | mislabelled (strict), non-tribal | mislabelled (strict), tribal |
|---|---|---|---|---|
| Overture | 2697 | 486 | 718 | 191 |
| meta | 2320 | 443 | 677 | 184 |
| Overture-signals | 1892 | 311 | 364 | 99 |
| BrightQuery | 231 | 15 | 21 | 0 |
| Foursquare | 137 | 23 | 13 | 2 |
| Microsoft | 9 | 5 | 7 | 3 |
| AllThePlaces | 0 | 0 | 0 | 2 |

## 6. The 12 named tracts in BIAS_DISCOVERY.md

| GEOID | tribal area | fire places under another label |
|---|---|---|
| 40061279300 | Choctaw OTSA | none |
| 40071001200 | Kaw OTSA | Kildare Fire Department (fire_protection_service, strict); Newkirk Fire Department EMS (fire_protection_service, strict); Dale Township Fire Department (community_services_non_profits, strict); River Road Volunteer Fire Department (fire_protection_service, strict) |
| 40089098900 | Choctaw OTSA | none |
| 40023967300 | Choctaw OTSA | Boswell Volunteer Fire Department (fire_protection_service, strict); Soper Volunteer Fire Department (fire_protection_service, strict); Nelson Volunteer Fire Department (business_manufacturing_and_supply, strict) |
| 40079040700 | Choctaw OTSA | Shoot Fire Shooters Archery Club (active_life, loose); Honobia Fire Tower (landmark_and_historical_building, loose) |
| 40085094300 | Chickasaw OTSA | Leon VFD (fire_protection_service, strict); Orr Volunteer Fire Department  (fire_protection_service, strict) |
| 40001376800 | Cherokee OTSA | none |
| 40029388200 | Choctaw OTSA | none |
| 40049681900 | Chickasaw OTSA | Pernell Volunteer Fire Department (fire_protection_service, strict) |
| 40051000702 | Chickasaw OTSA | none |
| 40055967100 | Kiowa-Comanche-Apache-Fort Sill Apache OTSA | none |
| 40055967200 | Kiowa-Comanche-Apache-Fort Sill Apache OTSA | Mangum Fire Department (fire_protection_service, strict) |

