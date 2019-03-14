import api.ScriptBase
import com.elektrobit.ebsolys.core.targetdata.api.runtime.eventhandling.Unit
import com.elektrobit.ebsolys.script.external.AfterScript
import com.elektrobit.ebsolys.script.external.BeforeScript
import com.elektrobit.ebsolys.script.external.Execute
import com.elektrobit.ebsolys.script.external.Execute.ExecutionContext
import com.elektrobit.ebsolys.script.external.ScriptContext
import com.google.gson.Gson
import com.google.gson.JsonElement
import com.google.gson.reflect.TypeToken
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.util.ArrayList
import java.util.List
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.eclipse.xtend.lib.annotations.Data

class FluentBitHttpServer {

	extension ScriptContext _scriptContext
	extension ScriptBase _scriptBase

	new(ScriptContext scriptContext) {
		_scriptContext = scriptContext
		_scriptBase = new ScriptBase(_scriptContext)
	}

	ExecutorService threadPool
	Gson gson	
	ServerSocket server
	val diskIOListType = new TypeToken<ArrayList<DiskIOItem>>(){}.getType();  
	val memoryListType = new TypeToken<ArrayList<MemoryItem>>(){}.getType();  
	val netifListType = new TypeToken<ArrayList<NetIfItem>>(){}.getType();  
	
	@BeforeScript
	def setup() {
		server = new ServerSocket(7071)
		threadPool = Executors.newCachedThreadPool
		gson = new Gson
	}

	@AfterScript
	def tearDown() 
	{
		consolePrintln('Tear Down invoked')
		threadPool.shutdownNow
		server.close
	}

	/**
	 * Add a meaningful content to the description tag to describe the feature, which is executed by this script
	 * The content of the description tag will be used in all UI widgets where the script can be invoked
	 * If the content is empty, then the classname.methodname will be used instead
	 */
	@Execute(context=ExecutionContext.GLOBAL, description="Start HTTP Server and listen to Fluentbit log records...")
	def execute() {

		while (true) {
			val socket = server.accept
			threadPool.execute(
				new Runnable() {
					override run() {
						val in = new BufferedReader(new InputStreamReader(socket.getInputStream()));
						val post = readHttpPostData(in)
						switch (post.getUri) {
							case 'memory': handleMemory(post.payload)
							case 'diskIO' : handleDiskIO(post.payload)
							case 'netif' : handleNetIf(post.payload)
							default: { consolePrintln(post.payload) }								
						}
					}
				}
			)
		}
	}
	
	def readHttpPostData(BufferedReader in)
	{
		val post = in.readLine
		val source = post.split(' ').get(1).substring(1)
		in.readLine // Host
		val len = Integer.parseInt(in.readLine.split(':').last.trim).intValue
		in.readLine // Content-Type
		in.readLine // User-Agent
		in.readLine // Empty Line		
		val char[] buffer = newCharArrayOfSize(len)
		in.read(buffer)
		
		new HttpPostData(source, new String(buffer))		
	}

	def handleDiskIO(String jsonString) {
				
		val List<DiskIOItem> diskIOList = gson.fromJson(jsonString, diskIOListType)
		
		diskIOList.forEach[
			val timestamp = date.asMicroSeconds
			createOrGetChannel("DiskIO.read", Unit.KILOBYTE, '').addEvent(timestamp, read.asKiloBytes)
			createOrGetChannel("DiskIO.write", Unit.KILOBYTE, '').addEvent(timestamp, write.asKiloBytes)
		]
	}

	def handleMemory(String jsonString) {
				
		val List<MemoryItem> memList = gson.fromJson(jsonString, memoryListType)
		
		memList.forEach[
			val timestamp = date.asMicroSeconds
			createOrGetChannel("Mem.total", Unit.KILOBYTE, '').addEvent(timestamp, total)
			createOrGetChannel("Mem.used", Unit.KILOBYTE, '').addEvent(timestamp, used)
			createOrGetChannel("Mem.free", Unit.KILOBYTE, '').addEvent(timestamp, free)
		]
	}
	
	def handleNetIf(String jsonString) {
				
		val List<NetIfItem> memList = gson.fromJson(jsonString, netifListType)
		
		memList.forEach[
			val timestamp = date.asMicroSeconds
			createOrGetChannel("Netif.rx.bytes", Unit.KILOBYTE, '').addEvent(timestamp, rxBytes.asKiloBytes)
			createOrGetChannel("Netif.rx.packets", Unit.COUNT, '').addEvent(timestamp, rxPackets)
			createOrGetChannel("Netif.tx.bytes", Unit.KILOBYTE, '').addEvent(timestamp, txBytes.asKiloBytes)
			createOrGetChannel("Netif.tx.packets", Unit.COUNT, '').addEvent(timestamp, txPackets)
		]
	}

	def asKiloBytes(long bytes)
	{
		bytes / 1024
	}

	def asMicroSeconds(double date)
	{
		(date*1000000).longValue
	}	
}

@Data
class DiskIOItem {
	double date
	long read
	long write
}

@Data
class MemoryItem {
	double date
	long total
	long used
	long free
}

@Data
class NetIfItem {
	double date
	long rxBytes
	long rxPackets
	long txBytes
	long txPackets 
}

@Data
class HttpPostData {
	String uri
	String payload		
}
