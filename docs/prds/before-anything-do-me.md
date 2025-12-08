change think 
remove driver from think as we have a new engine 

update workflow remove driver version from workflows remove rules from workflows 



for drivers, personas, rulesets, workflows 
understand this 
all MCP reads and writes to the data base 
we do not need the yaml files 
we dont keep the yaml files 
this data will be seeded 


there is a mongo i need a make task to connect to that mongo and run mongo console so i can query it 
it should be called make mongosh

in mongo we need savant_development and savant_test db 
all logs are stored in respective db for respective collections 
e.g. for mcp personas logs are in personas collection
driver logs are in drivers collection 

hub logs are in hub collection 

make sure all logs are stored accordingly 
also these logs need to be stdioed as well 

Once you have done that look at 
docs/prds/architecture/00-architecture-full.md

and there is an implementation plan in the same directory implement it one by one 
