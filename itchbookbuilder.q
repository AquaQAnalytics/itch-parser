/############################### User inputs ###############################
p:.Q.def[`init`date`size`hdb`tablename!(1b;.z.d;100;`HDB;`book)] .Q.opt .z.x

usage:{-1
  "
  ####################################### ITCH bookbuilder ################################################\n
  This script is used with the tables created by itchparser.q to build an orderbook for a day's trading.   \n
  The sample usage is as follows:                                                                          \n
  q itchbookbuilder.q -init 1 -date 2017.08.30 -size 50 -hdb HDB -tablename book                           \n
  init is a boolean which tells q to build and save the orderbook automatically. The dafault value is 1    \n
  date will default to today's date if none is provided                                                    \n
  size is the number of stocks to build the orderbook of at any one time. This is done to prevent memory   \n
  issues. It defaults to 100 stocks which was fast when tested on a machine with 16048 MB of RAM and 8     \n
  cores.                                                                                                   \n
  hdb is the location of the parsed itch files. The orderbook will save in this directory. The default 	   \n
  argument is HDB/								                                                                         \n
  tablename is what you wish to call the orderbook within the hdb. The default argument is book	           \n"
  ;exit[0]}
if[`usage in key p; usage[]]

/############################### Create pidmapping ###############################
gettables:{[o]
  system"l ",(string o[`hdb]),"/";
  replacetab::select from oreplace where date=o[`date];							                                /Obtain data for in memory table operations, i.e. union join.
  addtab::select from oadd where date=o[`date];
  addmpidtab::select from oaddmpid where date=o[`date]}
 
tableprep:{
 dict:exec (`u#origorderref)!neworderref from replacetab;						                                /When an order is replaced its id changes. Create a mapping where original order references are mapped to their new id.
 notreplaced:(uj/[{[x;y](select ids:orderref, stock, pid:orderref,side                              /Get those ids which are never replaced -and therefore don't appear in the oreplace table. 
     from x where not orderref in y)}[;key dict] each `addtab`addmpidtab]);
 idmapper:-1_'@[dict]\'[`u#exec origorderref except neworderref from replacetab];                   /Make lists starting with the parent id and all child ids oldest to newest.
 pidmapping:
 (
 ungroup											                                                                       
  {[a];([pid:a[;0]] ids:a) lj 
    1!uj/[{[x]select pid:orderref, stock,side from x} each (addtab;addmpidtab)]} idmapper           /Join the stock and side to the idmapper, as these do not appear anywhere but the add tables.
  )                                                                                                 /Ungroup is used to obtain a table with every id alongside it's parent id, stock and side.
  uj notreplaced						                                                                        /Join this to those ids which do not get replaced.
 ;pidmapping
 }
/############################### Building the orderbook ###############################
                                        
bookbuilder:{[d;syms]                                                                               /Create orderbook at each stage.
  bookbuild:{[t;act;ref;sd;sz;px]
        t:@[t;sd;,;$[act=`exec;`pid`shares!(ref;t[sd][ref;`shares]- sz);                        	  /If the action is exec remove the correct number of shares, else preform an upsert.
          `pid`shares`price!(ref;sz;px)]]; 
        if[0=t[sd][ref;`shares];									                                                  /If the number of shares in an order is zero, delete it. This takes care if the case
        t:@[t;sd;_;ref]];t};								 		                                                    /when the action is delete.
 
 bookbuildschema:([pid:`long$()]price:`float$();shares:`int$());
 
 symids:`ids xkey select from pidmapping where stock in syms;       					                      /Select relevant entries from the pidmapping for use with an inner join.
 
 ijid:exec ids from symids;
 
 itchdatapieces:(											                                                              /Since there is no stock to select, use ijid -based on symids above- to select by stock.
 select time,shares:0, ids:`u#orderref from odelete where orderref in ijid;
  select time,shares,price, ids:`u#origorderref from oreplace where origorderref in ijid;	          /This is a list of tables which we will then assign actions based on which table they came from.
  select time,shares,ids:orderref from oexecuted where orderref in ijid;			                      /This is used in the bookbuilder function.
  select time,shares:cancelled,ids:orderref from ocancel where orderref in ijid;
  select time,shares,ids:orderref from oexecutedwp where orderref in ijid
  );
 addordertable:enlist uj[select time,pid:orderref,side,shares,stock,price from oadd where date=d, stock in syms;
   select time,pid:orderref,side,shares,stock,price from oaddmpid where stock in syms];

 itchdata:update `g#action,`g#stock,`g#side from `time xasc delete id from				                  /Apply g attributes to speed reading for the bookbuilding.
  uj/[
    {[x;t]update action:x from t}'[`add`delete`replace`exec`exec`exec;					                    /Give tables their actions
  addordertable,ij\:[itchdatapieces;symids]]								                                        /Join the stock col to each of the tables found in the itchdatapieces. The add table is added to this list -no need to 
  ];													                                                                      /add the stock col here as it is already on this table.

 bidaskbook:update book:bookbuild\[("BS"!2#enlist bookbuildschema);action;pid;side;shares;price]    /Build two books, the bidbook and askbook.
    by stock from itchdata;
 
 bidbook:(`bpids`bprcs`bsizes xcol flip each 0!'(value'[exec book from bidaskbook])[;0]);		        /Extract the first book from the book col.
 askbook:(`apids`aprcs`asizes xcol flip each 0!'(value'[exec book from bidaskbook])[;1]);		        /Ditto for the second.
 b:(exec bsizes from bidbook)'
   [til count bidbook;(value each exec group each bprcs from bidbook)[til count bidbook]];		      /This creates a list of lists containing the bid sizes corresponding to each of the bid prices at each stage.
 a:(exec asizes from askbook)'
   [til count askbook;(value each exec group each aprcs from askbook)[til count askbook]];  		    /Ditto for ask.

 book:select time,stock,
        bbid:first each bprcs,
        bbsize:first each bsizes,
        bask:first each aprcs,
        basize:first each asizes,
        bprcs:distinct each bprcs,
        bsizes:`int${sum each x} each b,
        bno:`short${count each x} each b,
        aprcs:distinct each aprcs,
        asizes:`int${sum each x} each a,
        ano:`short${count each x} each a,
        bpids,
        apids
 from
 update apids:apids@'o,aprcs:aprcs@'o,asizes:asizes@'o,asizes,						                          /Set up positions of the prices so the sizes can be matched correctly to their price after being put in ascending/descending order.
        bpids:bpids@'v,bprcs:bprcs@'v,bsizes:bsizes@'v,bsizes						
          from update v:idesc'[bprcs],o:iasc'[aprcs]
            from (select time, stock from bidaskbook)							                                  /Join bid and askbook along with the time and stock.
              ,'bidbook
              ,'askbook
 ;book
 }

savebook:{[d;tablename;stock] hsym[`$(string d),"/",tablename,"/"] 
    upsert .Q.en[`:.;update value stock from uj/[bookbuilder[d;] peach stock]];.Q.gc[]}			        /Upsert each orderbook into an on disk table. This function will take in the hdb, a date and a list of syms. Books can be built
                                                                                                    /using multiple threads. Garbage collection is used so these books can be "forgotten" thus freeing memory for the next batch.
                                                    
/############################### Runtime function ###############################

init:{[o] 
  gettables[o];												                                                              /Load HDB.
  pidmapping::tableprep[];										                                                      /Create and save pidmapping.
  .Q.dpft[hsym `:.; o[`date];`stock;`pidmapping];
  c:value exec distinct stock from select stock from pidmapping;					                          /Obtains stocks in which to build orderbooks.
  savebook[o[`date];string o[`tablename];] each o[`size] cut c; 					                          /See the save book function above.
  `stock`time xasc hsym[`$":./",(string o[`date]),"/",(string o[`tablename])];
  @[hsym `$":./",(string o[`date]),"/",(string o[`tablename]),"/";`stock;`p#];                      /Adds the p attribute for fast lookup.
  exit[0]
  }

if[p[`init];@[init;p;{[p;x] -1 string[.z.p]," A fatal error occurred due to ",(raze string x);exit[0]}p]]
