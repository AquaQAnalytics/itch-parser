							/############################### User inputs ###############################

/NASDAQ files have the date in middle-endian format, so convert to big-endian.
p:.Q.def[`init`exit`itchfile`date`cutsize`save`saveto!(1b;1b;`$(string .z.d)[5 6 8 9 0 1 2 3],".PSX_ITCH_50";.z.d;20000;1b;`HDB)] .Q.opt .z.x
usage:{-1 
  "
  ######################################### ITCH Parser #################################################\n
  This script is used in order to convert ITCH messages into kdb+ tables. The sample usage is as follows:\n
  q itchparser.q -init 1 -exit 1 -itchfile 08302017.PSX_ITCH_50 -cutsize 20000 -save 1 -saveto HDB       \n
  init is a boolean which tells q to parse the file provided automatically. The default value is 1       \n
  exit is a boolean which tells q to exit on completion of the parsing                                   \n
  date will default to today's date if none is provided                                                  \n
  cutsize determines the number of syms which will be saved at any given time. It is important to match  \n
  to your systems specifications as too high a number will cause memory issues                           \n
  save is a boolean which tells q to save the tables. It defaults to 1                                   \n
  saveto is the location where the tables are to be saved.                                               \n
  This script can be used with slave threads. To start the script with slave threads use the flag -s     \n
  along with the number of cores you wish to use.                                                        \n"
  ;exit[0]}
if[`usage in key p; usage[]]

							/############################### Configuration ###############################

/This script is written using the specifications found in http://www.nasdaqtrader.com/content/technicalsupport/specifications/dataproducts/NQTVITCHSpecification.pdf.
/On updates to these specs, this is the section which requires editing. It is necessary that the order of the key is consistant for all of the dictionaries which use
/message type characters.

/The following contains a dictionary of casting functions which will be called via the types dictionary
typesf:(!) . flip 
  ((`intcon;  {256 sv x});
   (`alpha1;  {first "c"$x});
   (`alpha;   {"c"$x});
   (`tstmpcon;{[x]`timespan$ 256 sv x});
   (`price4;  {0.0001*256 sv x});
   (`price8;  {0.00000001*256 sv x});
   (`ipoqrt;  {[x]`timespan$00:00:00+256 sv x});
   (`sym;     {`$"c"$ x})
  )

msgoffsets:(!) . flip
  (("S";1 3 5 11);
   ("R";1 3 5 11 19 20 21 25 26 27 29 30 31 32 33 34 38);
   ("H";1 3 5 11 19 20 21);
   ("Y";1 3 5 11 19);
   ("L";1 3 5 11 15 23 24 25);
   ("V";1 3 5 11 19 27);
   ("W";1 3 5 11);
   ("K";1 3 5 11 19 23);
   ("A";1 3 5 11 19 20 24 32);
   ("F";1 3 5 11 19 20 24 32 36);
   ("E";1 3 5 11 19 23);
   ("C";1 3 5 11 19 23 31 32);
   ("X";1 3 5 11 19);
   ("D";1 3 5 11);
   ("U";1 3 5 11 19 27 31);
   ("P";1 3 5 11 19 20 24 32 36);
   ("Q";1 3 5 11 19 27 31 39);
   ("B";1 3 5 11);
   ("I";1 3 5 11 19 27 28 36 40 44 48 49);
   ("N";1 3 5 11 19)
  )

types:(!) . flip
  (("S";`intcon`intcon`tstmpcon`alpha1);
   ("R";`intcon`intcon`tstmpcon`sym`alpha1`alpha1`intcon`alpha1`alpha1`alpha`alpha1`alpha1`alpha1`alpha1`alpha1`intcon`alpha1);
   ("H";`intcon`intcon`tstmpcon`sym`alpha1`alpha1`alpha);
   ("Y";`intcon`intcon`tstmpcon`sym`alpha1);
   ("L";`intcon`intcon`tstmpcon`alpha`sym`alpha1`alpha1`alpha1);
   ("V";`intcon`intcon`tstmpcon`price8`price8`price8);
   ("W";`intcon`intcon`tstmpcon`alpha1);
   ("K";`intcon`intcon`tstmpcon`sym`ipoqrt`alpha1`price4);
   ("A";`intcon`intcon`tstmpcon`intcon`alpha1`intcon`sym`price4);
   ("F";`intcon`intcon`tstmpcon`intcon`alpha1`intcon`sym`price4`alpha);
   ("E";`intcon`intcon`tstmpcon`intcon`intcon`intcon);
   ("C";`intcon`intcon`tstmpcon`intcon`intcon`intcon`alpha1`price4);
   ("X";`intcon`intcon`tstmpcon`intcon`intcon);
   ("D";`intcon`intcon`tstmpcon`intcon);
   ("U";`intcon`intcon`tstmpcon`intcon`intcon`intcon`price4);
   ("P";`intcon`intcon`tstmpcon`intcon`alpha1`intcon`sym`price4`intcon);
   ("Q";`intcon`intcon`tstmpcon`intcon`sym`price4`intcon`alpha1);
   ("B";`intcon`intcon`tstmpcon`intcon);
   ("I";`intcon`intcon`tstmpcon`intcon`intcon`alpha1`sym`price4`price4`price4`alpha1`alpha1);
   ("N";`intcon`intcon`tstmpcon`sym`alpha1)
  )                
msgtypes:(!) . flip
  (("S";`systemevent);
   ("R";`stockdir);
   ("H";`stocktrdact);
   ("Y";`regsho);
   ("L";`mppos);
   ("V";`mwcbdecline);
   ("W";`mwcbbreach);
   ("K";`ipoqpu);
   ("A";`oadd);
   ("F";`oaddmpid);
   ("E";`oexecuted);
   ("C";`oexecutedwp);
   ("X";`ocancel);
   ("D";`odelete);
   ("U";`oreplace);
   ("P";`trademsgnc);
   ("Q";`crosstrademsg);
   ("B";`brokentrade);
   ("I";`noii);
   ("N";`rpii)
  )
/Set up table schemas

systemevent:([]stocklocate:();trackingno:();time:();event:());
stockdir:([]stocklocate:();trackingno:();time:();stock:();mktcat:();fstatus:();rlotsz:();rlotonly:();issueclass:();issuesub:();auth:();shtsaleti:();ipo:();luldrefpt:();etp:();etplev:();invind:());
stocktrdact:([]stocklocate:();trackingno:();time:();stock:();trdstate:();reserved:();reason:());
regsho:([]stocklocate:();trackingno:();time:();stock:();regshoact:());
mppos:([]stocklocate:();trackingno:();time:();mpid:();stock:();primm:();mmmode:();mpstate:());
mwcbdecline:([]stocklocate:();trackingno:();time:();lev1:();lev2:();lev3:());
mwcbbreach:([]stocklocate:();trackingno:();time:();breachlev:());
ipoqpu:([]stocklocate:();trackingno:();time:();stock:();ipoqreltime:();ipoqrelqual:();ipoprice:());
oadd:([]stocklocate:();trackingno:();time:();orderref:();side:();shares:();stock:();price:());
oaddmpid:([]stocklocate:();trackingno:();time:();orderref:();side:();shares:();stock:();price:();attribution:());
oexecuted:([]stocklocate:();trackingno:();time:();orderref:();shares:`int$();matchno:());
oexecutedwp:([]stocklocate:();trackingno:();time:();orderref:();shares:`int$();matchno:();printable:();price:());
ocancel:([]stocklocate:();trackingno:();time:();orderref:();cancelled:`int$());
odelete:([]stocklocate:();trackingno:();time:();orderref:());
oreplace:([]stocklocate:();trackingno:();time:();origorderref:();neworderref:();shares:`int$();price:());
trademsgnc:([]stocklocate:();trackingno:();time:();orderref:();side:();shares:();stock:();price:();matchno:());
crosstrademsg:([]stocklocate:();trackingno:();time:();shares:();stock:();crossprice:();matchno:();crosstype:());
brokentrade:([]stocklocate:();trackingno:();time:();matchno:());
noii:([]stocklocate:();trackingno:();time:();pairedshares:();imbshares:();imbdir:();stock:();farprice:();nrprice:();currefprice:();crosstype:();pricevar:());
rpii:([]stocklocate:();trackingno:();time:();stock:();interest:());

/################################ Parser ################################ 

/This section contains all the function which will parse the itch file.

setcutpoints:{[n] filebytesize:count n; 					                          /Get the size of the file to determine when to finish the function
  {[n;x]length: 256 sv n[x + 0 1] ; 						                            /The first two bytes of an ITCH message represent the length of that message, so select these and create a list of cut points which will be used to split 
    op,:x ; x:x +  length + 2; x}[n;]/						                          /the file into indivdual messages. op is a global varible
    [{x< y}[;filebytesize];0]}                                              / which is used for preformance reasons.

convertdata:{
  f:{[msgtyp;piece]
    cut[msgoffsets[msgtyp];] each   
    exec 2_'data from piece where msgtype=msgtyp}[;x] peach key msgtypes;	  /Insert these messages into the empty tables found in the config section. 
   {[x;y] {x@ raze y}'/:[typesf types[x];y]}'[key msgtypes;f]
  };

itchinserter:{upsert'[value msgtypes;convertdata x]}

readfile:{read1 hsym x}

/cut file into indivdual messages then create a table with message types and data corresponding to each message. Here n is an itch file and op is a global created by the cutter function.
createdataandtypes:{[n] c: op cut n; t:([] msgtype:"c"$ c[;2] ; data:c)}

saving:{[s;d;t]
  if[0=count value t;:()];
  $[`stock in cols[t];:.Q.dpft[hsym s;d;`stock;t];
  hsym[`$ "/" sv string (s),d,t,`] set .Q.en[hsym[s];value t]]
  };

savetables:{[o]
  saving[o[`saveto];o[`date]] each tables[]}

/############################### Runtime function ###############################

init:{[o]
  n:readfile[o[`itchfile]];                                                   /Read in itchfile.
  setcutpoints[n];                                                            /Set cut points for n as a global var called op.
  t:createdataandtypes[n];                                                    /Cuts and creates a table of messagetypes and data for each message in the ITCH file.
  pieces:o[`cutsize] cut t;                                                   /Breaks the table t created above into smaller pieces. The size of these pieces is specfied in the command line.
  itchinserter'[pieces];                                                      /Cast the data in a useable kdb format and insert them into tables.
  if[o[`save];savetables[o]];                                                 /Saves tables on disk as a partitioned database if the user wishes to.
  }

if[p[`init];
  @[init;p;{[p;x] -1 string[.z.p]," A fatal error occurred due to ",(raze string x);exit[0]}p]; 
  -1 string[.z.p]," Script executed successfully."; 
  if[p[`exit];exit[0]]] 
