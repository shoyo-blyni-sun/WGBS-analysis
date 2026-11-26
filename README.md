# WGBS-analysis
<h1 style="line-height:1;">Описание пайплайна Bismark / Nextflow</h1>
<h2>Назначение пайплайна</h2>
<p>Пайплайн выполняет анализ парных FASTQ-файлов после бисульфитного секвенирования:</p>
<p><strong>FastQC → выравнивание Bowtie2 → дедупликация → извлечение метилирования → сборка отчёта Bismark</strong></p>
<p>Пайплайн написан на Nextflow DSL2. К основному пайплайну прилагается config c описанием выполнения процессов.</p>
<p>Для проведения необходимо создать окружение (например,с помощью .yml файла)</p>
<p>Все файлы приложены в закрепах.</p>
<h2>Требования к окружению</h2>
<p>В скрипте нет контейнеров и фиксации версий, поэтому для воспроизводимости нужно отдельно зафиксировать:</p>
<ul>
<li>версию Nextflow;</li>
<li>версию <code>fastqc</code>;</li>
<li>версию <code>bismark</code>;</li>
<li>версию <code>bowtie2</code>;</li>
<li>версию <code>samtools</code>, если используется внутри Bismark;</li>
<li>сборку генома и версию индекса Bismark;</li>
</ul>
<p>Минимально в <code>PATH</code> должны быть доступны:</p>
<pre><code>nextflow
fastqc
bismark
bowtie2</code></pre>
<hr>
<h2>Входные данные</h2>
<h3>1. Samplesheet</h3>
<p>CSV-файл с заголовком и тремя обязательными колонками:</p>
<pre><code>sample,fastq_1,fastq_2
S1,/path/to/S1_R1.fastq.gz,/path/to/S1_R2.fastq.gz</code></pre>
<ul>
<li><code>sample</code> — уникальное имя образца;</li>
<li><code>fastq_1</code>, <code>fastq_2</code> — пути к парным FASTQ.</li>
</ul>
<h3>2. Индекс генома для Bismark</h3>
<p>Параметр <code>--genome_index</code> должен указывать на директорию с заранее подготовленным индексом Bismark/Bowtie2. Была выбрана Genome assembly GRCh38.p14 <a href="https://www.ncbi.nlm.nih.gov/datasets/genome/GCF_000001405.40/" target="_blank" rel="noreferrer noopener">Homo sapiens genome assembly GRCh38.p14 - NCBI - NLM</a> </p>
<p>Индекс должен быть создан командой <code>bismark_genome_preparation</code> в том же окружении - процесс не включен в пайплайн (используемые ресурсы: 16 cpu, память 64FG)</p>
<hr>
<h2>Параметры запуска</h2>
<p>Обязательные параметры:</p>
<ul>
<li><code>--samplesheet</code> — путь к CSV-samplesheet;</li>
<li><code>--genome_index</code> — путь к директории с индексом генома.</li>
</ul>
<p>Значения задаются в <code>nextflow.config</code>:</p>
<pre><code>params {
    genome_index = "/mnt/scratch/a_blinova/ncbi_dataset/data/GCF_000001405.40"
    samplesheet  = "samplesheet.csv"
}</code></pre>
<p>Пример запуска:</p>
<pre><code><span style="text-decoration:underline;"><em>nextflow -log ./logs/nextflow2.log run pype_final.nf -resume (параметр -resume для возможности запуска пайплайна с последнего выполненного места)</em></span></code></pre>
<hr>
<h2>Конфигурация ресурсов (Slurm)</h2>
<p>Пайплайн запускается через <code>executor = 'slurm'</code> в очереди <code>intbio</code>. Stdout и stderr каждого задания сохраняются в:</p>
<pre><code>/mnt/scratch/a_blinova/pype2/logs/slurm-%j.out
/mnt/scratch/a_blinova/pype2/logs/slurm-%j.err</code></pre>
<p>Ресурсы по процессам заданы в <code>nextflow.config</code>:</p>
<table>

<tr>
<th>Процесс</th>
<th>cpus</th>
<th>memory</th>
<th>time</th>
</tr>
<tr>
<td><code>FASTQC</code></td>
<td>1</td>
<td>30 GB</td>
<td>—</td>
</tr>
<tr>
<td><code>ALIGN</code></td>
<td>6</td>
<td>200 GB</td>
<td>100h</td>
</tr>
<tr>
<td><code>DeDUPLICATE</code></td>
<td>2</td>
<td>8 GB</td>
<td>100h</td>
</tr>
<tr>
<td><code>METH_CALL</code></td>
<td>—</td>
<td>50 GB</td>
<td>—</td>
</tr>

</table>
<blockquote>
<p>Параметр <code>cpus</code> имеет смысл задавать только для команд, которые действительно умеют использовать несколько потоков (например, <code>bismark --parallel</code> или <code>bismark dedup -p</code>). Для остальных процессов <code>cpus = 1</code> эквивалентно поведению по умолчанию.</p>
</blockquote>
<hr>
<h2>Этапы анализа</h2>
<table>

<tr>
<th>Этап</th>
<th>Процесс</th>
<th>Команда / логика</th>
<th>Основные выходы</th>
</tr>
<tr>
<td>QC ридов</td>
<td><code>FASTQC</code></td>
<td><code>fastqc ${fastq1} ${fastq2} -o .</code></td>
<td><code>results/fastqc/*.html</code>, <code>*.zip</code></td>
</tr>
<tr>
<td>Выравнивание</td>
<td><code>ALIGN</code></td>
<td><code>bismark --bowtie2 --parallel 3 --genome ${genome_dir} -o . -1 ${fastq1} -2 ${fastq2}</code></td>
<td><code>*bt2_PE_report.txt</code>, <code>*_bismark_bt2_pe.bam</code></td>
</tr>
<tr>
<td>Дедупликация</td>
<td><code>DeDUPLICATE</code></td>
<td><code>bismark dedup -p --bam ${bam_file}</code></td>
<td><code>*_bismark_bt2_pe.deduplicated.bam</code>, <code>*_bismark_bt2_pe.deduplication_report.txt</code></td>
</tr>
<tr>
<td>Извлечение метилирования</td>
<td><code>METH_CALL</code></td>
<td><code>bismark_methylation_extractor -p --bedGraph --buffer_size 30G ${bam_dedup_file}</code></td>
<td><code>*_pe.deduplicated.txt</code>, <code>*.bedGraph.gz</code>, <code>*.bismark.cov.gz</code>, <code>*_splitting_report.txt</code>, <code>*.M-bias.txt</code></td>
</tr>
<tr>
<td>Итоговый отчёт</td>
<td><code>REPORT</code></td>
<td><code>bismark report --alignment_report ... --dedup_report ... --splitting_report ... --mbias_report ...</code></td>
<td><code>results/report/*_PE_report.html</code></td>
</tr>

</table>
<p>Все результаты копируются в <code>results/</code> в соответствующие поддиректории:</p>
<pre><code>results/
├── fastqc/
├── align/
├── dedup/
├── meth_call/
└── report/</code></pre>
<p>Промежуточные файлы остаются в рабочей директории Nextflow <code>work/</code>.</p>
<hr>
<h2>Логика связывания процессов</h2>
<ol>
<li><code>reads_ch</code> читает samplesheet и создаёт кортежи <code>(sample, fastq_1, fastq_2)</code>.</li>
<li><code>FASTQC</code> запускается для всех образцов.</li>
<li><code>ALIGN</code> получает риды и директорию индекса генома.</li>
<li><code>DeDUPLICATE</code> получает BAM из <code>ALIGN</code>.</li>
<li><code>METH_CALL</code> получает дедуплицированный BAM.</li>
<li><code>REPORT</code> объединяет отчеты по всем командам:
<ul>
<li>alignment report из <code>ALIGN</code>;</li>
<li>deduplication report из <code>DeDUPLICATE</code>;</li>
<li>splitting report из <code>METH_CALL</code>;</li>
<li>M-bias report из <code>METH_CALL</code>.</li>
</ul>
</li>
</ol>
<hr>
<h2>Итоговый отчёт</h2>
<p>Процесс <code>REPORT</code> собирает единый HTML-отчёт по образцу (<code>results/report/*_PE_report.html</code>). Отчёт генерируется командой <code>bismark2report</code> (в скрипте — <code>bismark report</code>) и агрегирует четыре исходных текстовых отчёта, полученных на предыдущих этапах.</p>
<h3>Входные файлы отчёта</h3>
<table>

<tr>
<th>Аргумент</th>
<th>Источник</th>
<th>Содержимое</th>
</tr>
<tr>
<td><code>--alignment_report</code></td>
<td><code>ALIGN</code> → <code>*bt2_PE_report.txt</code></td>
<td>Статистика выравнивания парных прочтений Bowtie2</td>
</tr>
<tr>
<td><code>--dedup_report</code></td>
<td><code>DeDUPLICATE</code> → <code>*_deduplication_report.txt</code></td>
<td>Количество и доля удалённых дубликатов</td>
</tr>
<tr>
<td><code>--splitting_report</code></td>
<td><code>METH_CALL</code> → <code>*_splitting_report.txt</code></td>
<td>Количество метилированных/неметилированных цитозинов по контекстам</td>
</tr>
<tr>
<td><code>--mbias_report</code></td>
<td><code>METH_CALL</code> → <code>*.M-bias.txt</code></td>
<td>Профиль M-bias по позициям в прочтении</td>
</tr>

</table>
<h3>Что содержит итоговый HTML-отчёт</h3>
<ol>
<li><strong>Сводка по выравниванию.</strong>
<ul>
<li>Общее число прочтений и пар;</li>
<li>число уникально выровненных прочтений и доля от общего;</li>
<li>число прочтений с множественным выравниванием;</li>
<li>число невыровненных прочтений;</li>
</ul>
</li>
<li><strong>Сводка по дедупликации.</strong>
<ul>
<li>Сколько выровненных прочтений осталось после удаления дубликатов;</li>
<li>абсолютное число и процент дубликатов;</li>
<li>отдельно для уникальных и множественных выравниваний.</li>
</ul>
</li>
<li><strong>Статистика метилирования по контекстам.</strong>
<ul>
<li>CpG, CHG, CHH — процент метилированных цитозинов;</li>
<li>разбивка по цепям: OT, OB, CTOT, CTOB;</li>
<li>отдельные таблицы для уникальных и множественных выравниваний.</li>
</ul>
</li>
<li><strong>Cytosine methylation splitting report.</strong>
<ul>
<li>Число метилированных и неметилированных цитозинов в каждом контексте;</li>
<li>рассчитанный процент метилирования;</li>
<li>разделение по цепям и по типу выравнивания.</li>
</ul>
</li>
<li><strong>M-bias plots.</strong>
<ul>
<li>Графики уровня метилирования в зависимости от позиции в прочтении;</li>
<li>Отдельные кривые для CpG, CHG, CHH и для каждой цепи;</li>
</ul>
</li>
</ol>
<p>Полный репорт</p>
<h2>Полученные данные после Meth_call</h2>
<h4>Интерпретация результатов</h4>
</code><br><code>Bismark methylation extractor version v0.25.1</code><br><code>V350393166L1C001R00100001245/1  -       NC_000011.10    104642167       x</code><br><code>V350393166L1C001R00100001245/1  -       NC_000011.10    104642159       x</code><br><code>V350393166L1C001R00100001245/1  -       NC_000011.10    104642117       x</code><br><code>V350393166L1C001R00100001245/1  -       NC_000011.10    104642007       x</code><br><code>V350393166L1C001R00100001251/1  -       NC_000006.12    67934690        x</code><br><code>V350393166L1C001R00100001251/1  -       NC_000006.12    67934596        x</code></p>
<p>id рида - метилирование - номер хромосомы - позиция (старт=стоп) - метилирование (+контекст)</p>
<p> </p>
<h3><strong>Coverage.gz</strong></h3>
<p><code>NT_187489.1     379     379     0       0       1</code><br><code>NT_187490.1     387     387     0       0       2</code><br><code>NT_187490.1     565     565     33.3333333333333        1       2</code><br><code>NT_187490.1     657     657     0       0       3</code><br><code>NT_187490.1     664     664     0       0       3</code><br><code>NT_187492.1     979     979     0       0       1</code><br><code>NT_187492.1     982     982     0       0       1</code><br><code>NT_187492.1     1010    1010    0       0       1</code><br><br></p>
<p>Хромосома - Старт- Энд - процент метилированных ридов - метилированные риды - неметилированные риды</p>
<h3> </h3>
<h3><strong>M-bias plot</strong></h3>
<p><code>pG context (R1)</code><br><code>================</code><br><code>position        count methylated        count unmethylated      % methylation   coverage</code><br><code>1       914199  1024033 47.17   1938232</code><br><code>2       617315  600113  50.71   1217428</code><br><code>3       783139  951020  45.16   1734159</code><br><code>4       816195  1029769 44.22   1845964</code><br><code>5       843426  1031035 45.00   1874461</code><br><code>6       868695  1080349 44.57   1949044</code><br><code>7       793411  980989  44.71   1774400</code><br><code>8       846765  1029274 45.14   1876039</code><br><code>9       822421  1028699 44.43   1851120</code><br><code>10      806738  1016965 44.24   1823703</code></p>
<p><img src="app/download.php?f=b1/b12e4edc-4272-4d8e-a767-3f4ce646caee.png" width="400" height="400" alt="b12e4edc-4272-4d8e-a767-3f4ce646caee.png"></p>
<p> </p>
<h2>Краткая воспроизводимая схема</h2>
<p><code># 1. Подготовить окружение<br> 
### 2.Подготовить samplesheet.csv
### 3. Подготовить индекс генома
### 4. Заполнить nextflow.config (ресурсы и аргументы)
### 5. Запустить пайплайн:
<span style="text-decoration:underline;"><em>nextflow -log ./logs/nextflow2.log run pype_final2.nf</em></span>

# 6. Проверить результаты:
results/fastqc/
results/align/
results/dedup/
results/meth_call/
results/report/    ← итоговый HTML-отчёт по каждому образцу<br><br><br><br></code></p>
