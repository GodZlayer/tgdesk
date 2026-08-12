// Comando de ingestão do corpus externo (§13.2 e §14, trilha A1).
//
// Lê o Posts.xml do dump do Stack Exchange e popula o schema `corpus`. É
// ferramenta de CONSTRUÇÃO: roda fora do caminho de diagnóstico, contra o banco,
// e nada do que ela escreve é consultado em runtime.
//
// Uso:
//
//	corpusingest -7z ../TGDESK-corpus/superuser.com.7z -db postgres://...
//	corpusingest -xml Posts.xml -db postgres://...          (arquivo já extraído)
//	corpusingest -7z ... -limite 5000 -seco                 (ensaio, sem gravar)
//
// Por que ler direto do .7z: o Posts.xml do Superuser passa de 10 GB
// descomprimido. Extrair para disco só para depois varrer uma vez é pagar
// espaço que a máquina pode não ter — o descompressor vira um pipe.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/corpus"
)

func main() {
	var (
		caminho7z  = flag.String("7z", "", "caminho do dump .7z (lê Posts.xml em fluxo)")
		caminhoXML = flag.String("xml", "", "caminho de um Posts.xml já extraído")
		bin7z      = flag.String("7zbin", `C:\Program Files\7-Zip\7z.exe`, "executável do 7-Zip")
		dbURL      = flag.String("db", os.Getenv("DATABASE_URL"), "URL do Postgres")
		fonte      = flag.String("fonte", "superuser.com", "nome da fonte")
		licenca    = flag.String("licenca", "CC BY-SA 4.0", "licença do dump")
		limite     = flag.Int("limite", 0, "para depois de N perguntas aceitas (0 = tudo)")
		seco       = flag.Bool("seco", false, "não grava: só conta o que entraria")
	)
	flag.Parse()

	entrada, fechar, err := abrirPosts(*caminho7z, *caminhoXML, *bin7z)
	if err != nil {
		log.Fatalf("abrindo dump: %v", err)
	}
	defer fechar()

	var pool *pgxpool.Pool
	if !*seco {
		if *dbURL == "" {
			log.Fatal("faltou -db (ou DATABASE_URL); use -seco para ensaiar sem gravar")
		}
		pool, err = pgxpool.New(context.Background(), *dbURL)
		if err != nil {
			log.Fatalf("conectando ao banco: %v", err)
		}
		defer pool.Close()
	}

	ing := &ingestor{
		pool: pool, fonte: *fonte, licenca: *licenca,
		seco: *seco, limite: *limite,
		perguntas: map[int]*pergunta{},
	}
	if err := ing.rodar(entrada); err != nil {
		log.Fatalf("ingestão: %v", err)
	}
	ing.relatar()
}

// abrirPosts devolve o Posts.xml como fluxo, venha ele do .7z ou de um arquivo
// já extraído.
func abrirPosts(caminho7z, caminhoXML, bin7z string) (io.Reader, func(), error) {
	if caminhoXML != "" {
		f, err := os.Open(caminhoXML)
		if err != nil {
			return nil, nil, err
		}
		return f, func() { _ = f.Close() }, nil
	}
	if caminho7z == "" {
		return nil, nil, fmt.Errorf("informe -7z ou -xml")
	}
	// -so manda o conteúdo para a saída padrão: nada toca o disco.
	cmd := exec.Command(bin7z, "x", "-so", caminho7z, "Posts.xml")
	cmd.Stderr = os.Stderr
	saida, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, nil, err
	}
	return saida, func() { _ = cmd.Wait() }, nil
}

type pergunta struct {
	post      corpus.SEPost
	classe    string
	respostas []corpus.SEPost
}

type ingestor struct {
	pool    *pgxpool.Pool
	fonte   string
	licenca string
	seco    bool
	limite  int

	// As respostas aparecem DEPOIS da pergunta no dump, mas não
	// necessariamente logo depois. Guardar só as perguntas aceitas mantém a
	// memória proporcional ao domínio de interesse, não ao dump inteiro.
	perguntas map[int]*pergunta

	lidos, aceitas, respostas int
	// perguntas do domínio que eram configuração, não defeito
	configuracao    int
	gravadas, casos int
	porClasse       map[string]int
}

func (i *ingestor) rodar(r io.Reader) error {
	i.porClasse = map[string]int{}
	inicio := time.Now()

	err := corpus.LerPosts(r, func(p corpus.SEPost) error {
		i.lidos++
		if i.lidos%200000 == 0 {
			log.Printf("%d linhas lidas, %d perguntas aceitas (%s)",
				i.lidos, i.aceitas, time.Since(inicio).Round(time.Second))
		}

		switch p.PostTypeID {
		case 1:
			if !corpus.InteressaAoDominio(p.Tags, p.Title) {
				return nil
			}
			// Segundo filtro, e tão importante quanto o primeiro: a pergunta
			// tem que descrever um DEFEITO. O Superuser é, em grande parte,
			// site de "como faço" — e configuração não tem causa. Deixar isso
			// entrar como caso resolvido envenenaria os priors.
			if !corpus.EhCasoDeFalha(p.Title, corpus.LimparHTML(p.Body)) {
				i.configuracao++
				return nil
			}
			if i.limite > 0 && i.aceitas >= i.limite {
				return errParar
			}
			i.aceitas++
			classe := corpus.ClassePorTags(p.Tags, p.Title)
			i.porClasse[classe]++
			i.perguntas[p.ID] = &pergunta{post: p, classe: classe}
		case 2:
			q, ok := i.perguntas[p.ParentID]
			if !ok {
				// Resposta de pergunta fora do domínio: descartada sem custo.
				return nil
			}
			i.respostas++
			q.respostas = append(q.respostas, p)
		}
		return nil
	})
	if err != nil && err != errParar {
		return err
	}

	return i.gravarTudo()
}

var errParar = fmt.Errorf("limite atingido")

func (i *ingestor) gravarTudo() error {
	for _, q := range i.perguntas {
		// Pergunta sem resposta nenhuma não tem como render causa. Continua
		// valendo como vocabulário de sintoma, e é por isso que ela é gravada
		// como thread mesmo sem virar caso.
		sort.Slice(q.respostas, func(a, b int) bool {
			return q.respostas[a].CreationDate.Before(q.respostas[b].CreationDate)
		})
		if err := i.gravarThread(q); err != nil {
			return err
		}
	}
	return nil
}

func (i *ingestor) gravarThread(q *pergunta) error {
	// Monta a thread na forma que a rotulagem entende: a pergunta é o seq 1 e
	// pertence ao criador; as respostas vêm em ordem cronológica.
	posts := []corpus.Post{{
		Seq:       1,
		AutorID:   q.post.OwnerUserID,
		IsCriador: true,
		CorpoTxt:  corpus.LimparHTML(q.post.Body),
	}}
	for n, r := range q.respostas {
		posts = append(posts, corpus.Post{
			Seq:          n + 2,
			AutorID:      r.OwnerUserID,
			IsCriador:    r.OwnerUserID != "" && r.OwnerUserID == q.post.OwnerUserID,
			CorpoTxt:     corpus.LimparHTML(r.Body),
			RespondeA:    1,
			AceitaNativa: r.ID == q.post.AcceptedAnswerID,
		})
	}
	rot := corpus.Rotular(corpus.Thread{Posts: posts})

	if i.seco {
		i.gravadas++
		if rot.Desfecho == corpus.DesfechoResolvido {
			i.casos++
		}
		return nil
	}

	ctx := context.Background()
	var threadID string
	// ON CONFLICT: reingestão do dump converge, não soma (§13.7).
	err := i.pool.QueryRow(ctx, `
		INSERT INTO corpus.corpus_thread
			(fonte, fonte_id, url, titulo, licenca, data, autor_id_criador,
			 total_mensagens, resolvido_nativo)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
		ON CONFLICT (fonte, fonte_id) DO UPDATE
			SET titulo=EXCLUDED.titulo, total_mensagens=EXCLUDED.total_mensagens
		RETURNING id`,
		i.fonte, strconv.Itoa(q.post.ID),
		fmt.Sprintf("https://%s/q/%d", i.fonte, q.post.ID),
		q.post.Title, i.licenca, q.post.CreationDate, q.post.OwnerUserID,
		len(posts), q.post.AcceptedAnswerID != 0,
	).Scan(&threadID)
	if err != nil {
		return fmt.Errorf("thread %d: %w", q.post.ID, err)
	}

	// Reingestão: as mensagens são reescritas por completo, para que correção
	// de parser não deixe resíduo da versão anterior.
	if _, err := i.pool.Exec(ctx,
		`DELETE FROM corpus.corpus_post WHERE thread_id=$1`, threadID); err != nil {
		return err
	}
	// Um INSERT por mensagem seria uma ida ao banco por linha: com centenas de
	// milhares de mensagens, isso é a diferença entre minutos e horas. O lote
	// manda tudo de uma vez.
	brutos := append([]corpus.SEPost{q.post}, q.respostas...)
	lote := &pgx.Batch{}
	for n, p := range posts {
		primeira, ultima := corpus.PrimeiraEUltima(posts, p.AutorID)
		logs := corpus.ExtrairBlocosDeLog(brutos[n].Body)
		lote.Queue(`
			INSERT INTO corpus.corpus_post
				(thread_id, seq, autor_id, is_criador, is_primeira_do_autor,
				 is_ultima_do_autor, responde_a_seq, data, corpo_txt,
				 tem_bloco_log, logs_extraidos)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
			threadID, p.Seq, p.AutorID, p.IsCriador,
			p.Seq == primeira, p.Seq == ultima,
			nuloSeZero(p.RespondeA), brutos[n].CreationDate, p.CorpoTxt,
			len(logs) > 0, comoJSON(logs),
		)
	}
	if err := i.pool.SendBatch(ctx, lote).Close(); err != nil {
		return fmt.Errorf("mensagens da thread %d: %w", q.post.ID, err)
	}
	i.gravadas++

	// O caso é o produto da rotulagem. Threads sem informação causal entram com
	// o motivo do descarte — some do treino, fica no vocabulário.
	if _, err := i.pool.Exec(ctx, `
		INSERT INTO corpus.corpus_case
			(thread_id, sintoma_normalizado, desfecho, seq_da_causa,
			 classe_problema, motivo_descarte)
		VALUES ($1,$2,$3,$4,$5,$6)
		ON CONFLICT (thread_id) DO UPDATE
			SET desfecho=EXCLUDED.desfecho, seq_da_causa=EXCLUDED.seq_da_causa,
			    motivo_descarte=EXCLUDED.motivo_descarte`,
		threadID, q.post.Title, rot.Desfecho,
		nuloSeZero(rot.SeqDaCausa), q.classe, nuloSeVazio(rot.MotivoDescarte),
	); err != nil {
		return fmt.Errorf("caso %d: %w", q.post.ID, err)
	}
	if rot.Desfecho == corpus.DesfechoResolvido {
		i.casos++
	}
	return nil
}

func (i *ingestor) relatar() {
	log.Printf("linhas lidas:        %d", i.lidos)
	log.Printf("perguntas aceitas:   %d", i.aceitas)
	log.Printf("descartadas (configuração, não defeito): %d", i.configuracao)
	log.Printf("respostas vinculadas:%d", i.respostas)
	log.Printf("threads gravadas:    %d", i.gravadas)
	log.Printf("casos com causa:     %d", i.casos)
	log.Print("por classe de problema (cobertura é medida por classe, nunca em agregado):")
	classes := make([]string, 0, len(i.porClasse))
	for c := range i.porClasse {
		classes = append(classes, c)
	}
	sort.Strings(classes)
	for _, c := range classes {
		log.Printf("  %-12s %d", c, i.porClasse[c])
	}
}

func nuloSeZero(n int) any {
	if n == 0 {
		return nil
	}
	return n
}

func nuloSeVazio(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func comoJSON(v []string) string {
	if len(v) == 0 {
		return "[]"
	}
	saida := "["
	for n, s := range v {
		if n > 0 {
			saida += ","
		}
		saida += strconv.Quote(s)
	}
	return saida + "]"
}
